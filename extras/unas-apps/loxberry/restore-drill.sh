#!/bin/bash
# Restore drill for LoxBerry from the recovery set (run on the Mac).
#
#   extras/unas-apps/loxberry/restore-drill.sh root@<UNAS-IP> [--set <dir on the UNAS>] [--keep | --cleanup]
#
#   --keep     leave the test container, tag and directory for a look
#              (docker exec -it loxberry-restoretest bash)
#   --cleanup  only remove what a --keep run left
#
# Shows that the set brings LoxBerry back, with the live container untouched:
# loxberry-volume.tar.zst is unpacked into <pool>/.unas-apps/restoretest and
# images/loxberry-unas_live.tar.zst is loaded as loxberry-restoretest:live. A
# plain `docker load` would move loxberry-unas:live, which the stack runs, so
# the name is rewritten in the stream (RepoTags in manifest.json, index.json,
# repositories); the image ID stays that of the saved image. The container gets
# the options of the loxberry service in docker-compose.yml, but another name,
# no network, the scratch directory as /opt/loxberry and no restart. The report:
# systemd's state, failed units, services missing compared with the live
# container (plugins that need their cloud may wait to restart without a
# network), Apache, the plugins with their files, the MQTT gateway's settings
# and the config files changed since the backup.
#
# Default set: <pool>/.unas-apps/backup/recovery. Needs about 4 GB on the pool;
# below 300 MB of free memory the test stops. Repeat it after larger LoxBerry
# changes (docs/RECOVERY.md).
set -Eeuo pipefail
usage="usage: $0 root@<UNAS-IP> [--set <dir on the UNAS>] [--keep | --cleanup]"
target=${1:?$usage}
shift
set_dir='' mode=all
while (( $# )); do
    case "$1" in
        --set) set_dir=${2:?$usage}; shift ;;
        --keep) mode=keep ;;
        --cleanup) mode=cleanup ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

remote "SET='$set_dir' MODE='$mode' bash -s" <<'EOF'
set -euo pipefail
volume=$(for v in /volume/*-*-*-*-*; do mountpoint -q "$v" && echo "$v" && break; done)
[ -n "$volume" ] || { echo 'no mounted storage pool' >&2; exit 1; }
A="$volume/.unas-apps"
B=${SET:-$A/backup/recovery}
T="$A/restoretest"
NAME=loxberry-restoretest
TAG=loxberry-restoretest:live
mem() { awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo; }
x() { docker exec "$NAME" "$@"; }
services() { docker exec "$1" systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $1}' | sort; }

cleanup() {
    if docker container inspect "$NAME" >/dev/null 2>&1; then
        [ "$(docker inspect -f '{{index .Config.Labels "unas.restoretest"}}' "$NAME")" = 1 ] \
            || { echo "$NAME is not a test container, left alone" >&2; return 1; }
        docker stop -t 90 "$NAME" >/dev/null; docker rm "$NAME" >/dev/null
    fi
    if docker image inspect "$TAG" >/dev/null 2>&1; then docker rmi "$TAG" >/dev/null; fi
    rm -rf "$T"
    echo "test container, $TAG and $T removed"
}
if [ "$MODE" = cleanup ]; then cleanup; exit; fi

docker container inspect "$NAME" >/dev/null 2>&1 && { echo "$NAME exists; run with --cleanup first" >&2; exit 1; }
docker image inspect "$TAG" >/dev/null 2>&1 && { echo "$TAG exists; run with --cleanup first" >&2; exit 1; }
[ ! -e "$T" ] || { echo "$T exists; run with --cleanup first" >&2; exit 1; }
for f in SHA256SUMS loxberry-volume.tar.zst images/loxberry-unas_live.tar.zst; do
    [ -f "$B/$f" ] || { echo "no $f in $B" >&2; exit 1; }
done
free=$(df -Pm "$A" | awk 'NR == 2 {print $4}')
[ "$free" -gt 4096 ] || { echo "only $free MB free on the pool" >&2; exit 1; }
[ "$(mem)" -gt 600 ] || { echo "only $(mem) MB of memory available" >&2; exit 1; }
[ "$MODE" = keep ] || trap 'cleanup' EXIT

echo "set: $(head -1 "$B/MANIFEST.txt" 2>/dev/null || echo "$B")"
(cd "$B" && grep -E ' \./(loxberry-volume\.tar\.zst|images/loxberry-unas_live\.tar\.zst)$' SHA256SUMS | sha256sum -c -)
mkdir -p "$T/opt-loxberry"
zstd -dc "$B/loxberry-volume.tar.zst" | tar -C "$T/opt-loxberry" -xp
echo "volume: $(du -sh "$T/opt-loxberry" | cut -f1), $(find "$T/opt-loxberry" | wc -l) entries"

cat > "$T/retag.py" <<'PY'
# docker save tar from stdin to stdout with the image name changed:
#   retag.py <old repo:tag> <new repo:tag>; everything else copied unchanged
import io, json, sys, tarfile

old, new = sys.argv[1], sys.argv[2]
old_repo, old_tag = old.rsplit(":", 1)
new_repo, new_tag = new.rsplit(":", 1)
seen = set()

def rewrite(name, data):
    doc = json.loads(data)
    if name == "manifest.json":
        for m in doc:
            if old not in (m.get("RepoTags") or []):
                sys.exit(f"retag: {old} not in manifest.json RepoTags {m.get('RepoTags')}")
            m["RepoTags"] = [new]
    elif name == "index.json":
        for m in doc.get("manifests", []):
            a = m.get("annotations") or {}
            if "io.containerd.image.name" in a:
                a["io.containerd.image.name"] = "docker.io/library/" + new
            if "org.opencontainers.image.ref.name" in a:
                a["org.opencontainers.image.ref.name"] = new_tag
    elif name == "repositories":
        doc = {new_repo: {new_tag: v} for v in doc.get(old_repo, {}).values()}
    seen.add(name)
    return json.dumps(doc).encode()

with tarfile.open(fileobj=sys.stdin.buffer, mode="r|") as tin, \
        tarfile.open(fileobj=sys.stdout.buffer, mode="w|", format=tarfile.PAX_FORMAT) as tout:
    for m in tin:
        if m.isfile() and m.name in ("manifest.json", "index.json", "repositories"):
            data = rewrite(m.name, tin.extractfile(m).read())
            m.size = len(data)
            tout.addfile(m, io.BytesIO(data))
        elif m.isfile():
            tout.addfile(m, tin.extractfile(m))
        else:
            tout.addfile(m)

if "manifest.json" not in seen:
    sys.exit("retag: no manifest.json in the stream")
PY
start=$(date +%s)
nice -n 10 zstd -dc "$B/images/loxberry-unas_live.tar.zst" \
    | nice -n 10 python3 -I "$T/retag.py" loxberry-unas:live "$TAG" | docker load >/dev/null
loaded=$(docker image inspect -f '{{.Id}}' "$TAG")
saved=$(cat "$B/images/loxberry-unas_live.tar.zst.id" 2>/dev/null || true)
echo "image loaded in $(( $(date +%s) - start )) s: ${loaded:7:12}$([ -z "$saved" ] || { [ "$saved" = "$loaded" ] && echo ', the saved ID' || echo ", NOT the saved ID ${saved:7:12}"; })"

# sysctl, module loading and udev coldplug act on the NAS kernel; the image
# masks them since 2026-10, the mounts cover sets made before
docker run -d --name "$NAME" --hostname loxberry --network none \
    --privileged --cgroupns host --stop-signal SIGRTMIN+3 --restart no \
    --tmpfs /run --tmpfs /run/lock --tmpfs /tmp:exec \
    -v "$T/opt-loxberry:/opt/loxberry" -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    -v /dev/null:/etc/systemd/system/systemd-udev-trigger.service:ro \
    -v /dev/null:/etc/systemd/system/systemd-sysctl.service:ro \
    -v /dev/null:/etc/systemd/system/systemd-modules-load.service:ro \
    --label unas.restoretest=1 "$TAG" >/dev/null
state=starting
for i in $(seq 1 60); do
    sleep 10
    state=$(x systemctl is-system-running 2>/dev/null || true)
    [ "$(mem)" -ge 300 ] || { echo "only $(mem) MB of memory left, test stopped" >&2; exit 1; }
    case "$state" in running|degraded) break ;; esac
done
echo "systemd: $state after $((i * 10)) s, failed units: $(x systemctl --failed --no-legend --plain | awk '{print $1}' | paste -sd' ' | grep . || echo none)"
# without a network, plugins that need a cloud may fail and wait to restart
sleep 30
missing=$(comm -23 <(services loxberry) <(services "$NAME"))
echo "services running live but not in the test (no network): $(echo "$missing" | grep -c . || true)"
for s in $missing; do
    out=$(x journalctl _SYSTEMD_UNIT="$s" -n 1 -o cat --no-pager 2>/dev/null | cut -c1-120)
    echo "  $s: $(x systemctl show -p ActiveState -p SubState --value "$s" | paste -sd/), last output: ${out:-none in the journal}"
done
echo "apache: / $(x curl -s -o /dev/null -w '%{http_code}' http://localhost/), /admin/ $(x curl -s -o /dev/null -w '%{http_code}' http://localhost/admin/)"
echo "LoxBerry $(x jq -r '.Base.Version' /opt/loxberry/config/system/general.json), plugins:"
x jq -r '.plugins[] | "\(.title)\t\(.version)\t\(.folder)"' /opt/loxberry/data/system/plugindatabase.json \
    | while IFS=$'\t' read -r t v f; do
        has() { x test -d "$1" && echo yes || echo NO; }
        echo "  $t $v: bin $(has /opt/loxberry/bin/plugins/$f), web $(has /opt/loxberry/webfrontend/htmlauth/plugins/$f), config $(has /opt/loxberry/config/plugins/$f)"
    done
echo "MQTT gateway: $(x pgrep -fc mqttgateway.pl || true) process, $(x jq -r '"\((.subscriptions // []) | length) subscriptions, \((.subscriptionfilters // []) | length) filters, \((.Noncached // {}) | length) non-cached"' /opt/loxberry/config/system/mqttgateway.json), broker login $(x jq -r 'if (.Mqtt.Brokeruser // "") != "" and (.Mqtt.Brokerpass // "") != "" then "set" else "MISSING" end' /opt/loxberry/config/system/general.json)"
lv=$(docker volume inspect -f '{{.Mountpoint}}' unas-apps_loxberry)
echo "config files changed since the backup:"
diff -rq "$T/opt-loxberry/config" "$lv/config" 2>/dev/null | sed "s|$T/opt-loxberry|<restored>|g; s|$lv|<live>|g; s/^/  /" | head -20 || true
echo "memory available during the test: $(mem) MB"
EOF
