#!/bin/bash
# Update LoxBerry in its container with LoxBerry's own updater (run on the Mac).
#
#   extras/unas-apps/loxberry/update-loxberry.sh root@<UNAS-IP> [major] [container]
#
# LoxBerry only installs releases of its current major version; [major] (e.g. 4)
# allows the next one, as "allow upgrade" on its update page does
# (Update.max_version). LoxBerry 4 still ships a Debian 12 package list, so the
# container stays on bookworm (Debian 13's systemd refuses the UNVR's cgroup v1).
#
# Before the update the container is committed to loxberry-unas:pre-update and
# the volume is saved to <pool>/.unas-apps/backup/loxberry-volume-pre-update.tar.zst;
# the output ends with the rollback commands. The updater installs packages
# into the container layer, so afterwards the container is committed to the
# :live image the stack runs, then restarted (LoxBerry asks for a reboot).
set -Eeuo pipefail
target=${1:?usage: $0 root@<UNAS-IP> [major] [container]}
major=${2:-}
c=${3:-loxberry}
[[ -z "$major" || "$major" =~ ^[0-9]+$ ]] || { echo 'major: a number, e.g. 4' >&2; exit 2; }
[[ "$c" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo 'invalid container name' >&2; exit 2; }
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

remote "bash -s -- '$c' '$major'" <<'SH'
set -Eeuo pipefail
c=$1 major=$2
lbenv='set -a; . /etc/environment; set +a'
gen=/opt/loxberry/config/system/general.json
version() { docker exec "$c" python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["Base"]["Version"])' "$gen"; }
img=$(docker container inspect -f '{{.Config.Image}}' "$c")
case "$img" in *:live) ;; *) echo "$c runs $img; switch its stack to loxberry-unas:live first (install-on-unas.sh --up)" >&2; exit 1 ;; esac
A=$(ls -d /volume/*/.unas-apps | head -1)
lv=$(docker container inspect -f '{{range .Mounts}}{{if eq .Destination "/opt/loxberry"}}{{.Source}}{{end}}{{end}}' "$c")
[ -d "$lv" ] || { echo "no /opt/loxberry volume on $c" >&2; exit 1; }
before=$(version)
echo "LoxBerry $before"

# 1. rollback point: container layer and volume
docker commit --pause=false -m "LoxBerry $before, before update" "$c" loxberry-unas:pre-update >/dev/null
mkdir -p "$A/backup"
rc=0; tar -C "$lv" -cf - . | zstd -q -T0 -f -o "$A/backup/loxberry-volume-pre-update.tar.zst" || rc=$?
[ "$rc" -le 1 ] || { echo "volume backup failed ($rc)" >&2; exit 1; }   # 1: a file changed while read
echo "rollback point: loxberry-unas:pre-update, $A/backup/loxberry-volume-pre-update.tar.zst ($(du -h "$A/backup/loxberry-volume-pre-update.tar.zst" | cut -f1))"

# 2. allow the next major version
if [ -n "$major" ]; then
    docker exec "$c" python3 -c '
import json, os, sys
f, v = sys.argv[1], sys.argv[2]
d = json.load(open(f))
d.setdefault("Update", {})["max_version"] = v
json.dump(d, open(f + ".new", "w"), indent=1)
os.replace(f + ".new", f)' "$gen" "v$major.99.99"
    docker exec "$c" chown loxberry:loxberry "$gen"
    echo "allowed up to v$major.99.99"
fi

# 3. LoxBerry's updater: downloads the newest release, runs the update scripts
#    of every version in between (minutes on a busy RAID)
docker exec "$c" bash -c "$lbenv; perl /opt/loxberry/sbin/loxberryupdatecheck.pl querytype=release update=1 nofork=1 output=json" \
    > /tmp/lbupdate.out 2>&1 || true
after=$(version)
log=$(docker exec "$c" sh -c 'ls -t /opt/loxberry/log/system/loxberryupdate/*_update.log 2>/dev/null | head -1')
[ -z "$log" ] || docker exec "$c" grep -E '<(WARNING|ERROR|CRITICAL|ALERT)>' "$log" | tail -15 || true
if [ "$after" = "$before" ]; then
    echo "no update installed (still $before); updater output:" >&2
    tail -20 /tmp/lbupdate.out >&2; rm -f /tmp/lbupdate.out; exit 1
fi
rm -f /tmp/lbupdate.out
echo "updated: $before -> $after (log: ${log:-none})"

# 4. keep the packages the update installed, then the reboot it asks for
docker commit --pause=false -m "LoxBerry $after, $(date -Is)" "$c" "$img" >/dev/null
echo "committed $c -> $img"
docker restart -t 60 "$c" >/dev/null
for _ in $(seq 60); do
    code=$(docker exec "$c" curl -s -o /dev/null -w '%{http_code}' http://localhost/ 2>/dev/null || true)
    [ "$code" = 200 ] && break; sleep 5
done
echo "web interface after restart: HTTP ${code:-none}"
docker exec "$c" systemctl --failed --no-legend --plain 2>/dev/null | sed 's/^/failed unit: /' || true
cat <<TXT

Rollback, if needed (on the UNAS):
  docker stop $c && docker tag loxberry-unas:pre-update $img
  find $lv -mindepth 1 -delete && zstd -dc $A/backup/loxberry-volume-pre-update.tar.zst | tar -C $lv -xp
  docker rm $c && (cd $A/data/stacks/unas-apps && docker compose up -d)
When all is well: docker rmi loxberry-unas:pre-update; rm $A/backup/loxberry-volume-pre-update.tar.zst
TXT
SH
