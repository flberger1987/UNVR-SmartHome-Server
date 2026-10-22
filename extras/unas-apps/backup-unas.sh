#!/bin/bash
# Recovery set for the UNAS apps (run on the Mac): installs the backup on the
# UNAS (script, settings, optional weekly timer) and runs it once.
#
#   extras/unas-apps/backup-unas.sh root@<UNAS-IP> [--share <Drive share>] [--weekly] [--sd-image] [--no-run]
#
#   --share NAME  keep everything in the UniFi Drive share NAME, folder
#                 UNAS-Recovery/ (e.g. a share that Drive backs up to OneDrive);
#                 <pool>/.unas-apps/backup/recovery then links to it.
#                 Default: <pool>/.unas-apps/backup/
#   --weekly      run every Sunday 01:00 on the UNAS (before nightly cloud syncs)
#   --sd-image    also write a fresh image of the boot medium (7.5 GB, rarely needed)
#   --no-run      only install
#
# On the UNAS afterwards: unas-backup [--sd-image]. Result in <dest>/recovery/
# (images that did not change since the last run are skipped):
#   images/<image>.tar.zst      docker save of each image the stacks use;
#                               UniFi OS installs its apps (Protect, Network
#                               updates) into the container layer, so the UniFi
#                               OS stacks run <image>:live and the running
#                               containers are committed to it first
#   config.tar.zst              stacks (compose.yaml, .env, resolv.conf), Dockge,
#                               identities of the UniFi OS containers, daemon.json
#   host-files.tar.zst          host units/scripts/settings, for reference
#   loxberry-volume.tar.zst     LoxBerry's /opt/loxberry volume
#   network/                    newest UniFi Network backups (.unf)
#   SYSTEM.md                   private system sheet, if kept as <dest>/SYSTEM.md
#   MANIFEST.txt, SHA256SUMS
# and with --sd-image <dest>/sd-card/sd-boot.img.zst (+ .sha256, .sfdisk, .date).
# The data is stored unencrypted; it holds Wi-Fi and device credentials.
set -Eeuo pipefail
usage="usage: $0 root@<UNAS-IP> [--share <Drive share>] [--weekly] [--sd-image] [--no-run]"
target=${1:?$usage}
shift
share='' weekly=false sd=false run=true
while (( $# )); do
    case "$1" in
        --share) share=${2:?$usage}; shift ;;
        --weekly) weekly=true ;;
        --sd-image) sd=true ;;
        --no-run) run=false ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[[ -z "$share" || "$share" =~ ^[A-Za-z0-9._\ -]+$ ]] || { echo 'invalid share name' >&2; exit 2; }
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

remote "SHARE='$share' WEEKLY='$weekly' bash -s" <<'EOF'
set -euo pipefail
volume=$(for v in /volume/*-*-*-*-*; do mountpoint -q "$v" && echo "$v" && break; done)
[ -n "$volume" ] || { echo 'no mounted storage pool' >&2; exit 1; }
A="$volume/.unas-apps"
if [ -n "$SHARE" ]; then
    s="$volume/.srv/.unifi-drive/$SHARE/.data"
    [ -d "$s" ] || { echo "no UniFi Drive share \"$SHARE\" ($s)" >&2; exit 1; }
    DEST="$s/UNAS-Recovery" OWNER=$(stat -c %U:%G "$s")
else
    DEST="$A/backup" OWNER=''
fi
mkdir -p "$DEST/recovery"
# one recovery set: move an older one into the share and link the old path
if [ "$DEST" != "$A/backup" ]; then
    if [ -d "$A/backup/recovery" ] && [ ! -L "$A/backup/recovery" ]; then
        cp -a "$A/backup/recovery/." "$DEST/recovery/" && rm -rf "$A/backup/recovery"
    fi
    ln -sfn "$DEST/recovery" "$A/backup/recovery"
    if [ -f "$A/backup/SYSTEM.md" ] && [ ! -L "$A/backup/SYSTEM.md" ]; then
        mv "$A/backup/SYSTEM.md" "$DEST/SYSTEM.md" && ln -s "$DEST/SYSTEM.md" "$A/backup/SYSTEM.md"
    fi
fi
printf 'DEST="%s"\nOWNER="%s"\n' "$DEST" "$OWNER" > /etc/unas-backup.conf

cat > /usr/local/sbin/unas-backup <<'SH'
#!/bin/bash
# Recovery set of the UNAS apps (installed by extras/unas-apps/backup-unas.sh).
#   unas-backup [--sd-image]
set -euo pipefail
. /etc/unas-backup.conf
volume=$(for v in /volume/*-*-*-*-*; do mountpoint -q "$v" && echo "$v" && break; done)
A="$volume/.unas-apps" B="$DEST/recovery"
mkdir -p "$B/images" "$B/network"
z() { nice -n 19 ionice -c3 zstd -T2 -6 -q "$@"; }
exec 9>/run/unas-backup.lock; flock -n 9 || { echo 'another unas-backup is running' >&2; exit 1; }

# images of all stacks (also those in optional profiles)
images=$(sed -n 's/^ *image: *\([^ #"]*\).*/\1/p' "$A"/data/stacks/*/compose.yaml "$A"/dockge/compose.yaml | sort -u)
# UniFi OS containers: freeze the container layer (installed apps) into the
# :live image their stack runs
for c in unifi-os unifi-protect; do
    docker container inspect "$c" >/dev/null 2>&1 || continue
    img=$(docker container inspect -f '{{.Config.Image}}' "$c")
    case "$img" in *:live) ;; *) echo "$c does not run a :live image ($img), not committed"; continue ;; esac
    docker commit --pause=false -m "live state of $c, $(date -Is)" "$c" "$img" >/dev/null
    echo "committed $c -> $img"
done
for img in $images; do
    id=$(docker image inspect -f '{{.Id}}' "$img" 2>/dev/null) || { echo "missing image $img (skipped)"; continue; }
    f="$B/images/$(echo "$img" | tr '/:' '__').tar.zst"
    if [ -f "$f" ] && [ "$(cat "$f.id" 2>/dev/null)" = "$id" ]; then echo "unchanged $img"; continue; fi
    docker save "$img" | z -o "$f.part" && mv "$f.part" "$f" && echo "$id" > "$f.id"
    echo "saved $img ($(du -h "$f" | cut -f1))"
done
# drop saved images no stack uses any more
keep=$(for img in $images; do echo "$(echo "$img" | tr '/:' '__').tar.zst"; done)
for f in "$B"/images/*.tar.zst; do
    [ -e "$f" ] || continue
    grep -qx -F "$(basename "$f")" <<< "$keep" || { rm -f "$f" "$f.id"; echo "removed stale $(basename "$f")"; }
done

# stack configuration and identities (relative to <pool>/.unas-apps)
(cd "$A" && tar -cf - --ignore-failed-read data/stacks dockge docker/daemon.json \
    $(ls -d uckp/system.info uckp/board.info uckp/mtd protect/system.info protect/board.info 2>/dev/null) \
    ) | z -o "$B/config.tar.zst.part" && mv "$B/config.tar.zst.part" "$B/config.tar.zst"

# host files for reference (recreated by the install scripts)
tar -C / -cf - --ignore-failed-read $(cd / && ls -d usr/local/sbin/unas-* usr/local/bin/docker \
    etc/systemd/system/unas-* etc/systemd/system/var-tmp.mount etc/systemd/journald.conf.d/90-unas-* \
    etc/postgresql/14/main/conf.d/90-unas-* etc/unas-backup.conf root/.ssh/authorized_keys 2>/dev/null) 2>/dev/null \
    | z -o "$B/host-files.tar.zst.part" && mv "$B/host-files.tar.zst.part" "$B/host-files.tar.zst"

# private system sheet
if [ -f "$DEST/SYSTEM.md" ]; then cp -p "$DEST/SYSTEM.md" "$B/SYSTEM.md"
elif [ -f "$A/backup/SYSTEM.md" ]; then cp -pL "$A/backup/SYSTEM.md" "$B/SYSTEM.md"; fi

# LoxBerry's data volume
lv=$(docker volume inspect -f '{{.Mountpoint}}' unas-apps_loxberry 2>/dev/null || true)
if [ -n "$lv" ]; then
    tar -C "$lv" -cf - --warning=no-file-changed . 2>/dev/null \
        | z -o "$B/loxberry-volume.tar.zst.part" && mv "$B/loxberry-volume.tar.zst.part" "$B/loxberry-volume.tar.zst"
fi

# newest Network backups: UniFi OS container, standalone controller
for d in "$A"/uckp/data/unifi/data/backup/autobackup "$A"/data/unifi-network-application/data/backup/autobackup; do
    [ -d "$d" ] || continue
    { ls -t "$d"/*.unf 2>/dev/null || true; } | head -2 | while read -r f; do cp -p "$f" "$B/network/"; done
done
{ ls -t "$B"/network/*.unf 2>/dev/null || true; } | tail -n +7 | xargs -r rm -f

# image of the boot medium (on request)
if [ "${1:-}" = --sd-image ]; then
    sdd="$DEST/sd-card"; mkdir -p "$sdd"
    sfdisk -d /dev/boot > "$sdd/sd-boot.sfdisk" 2>/dev/null || true
    nice -n 19 ionice -c3 dd if=/dev/boot bs=4M status=none | z -3 -o "$sdd/sd-boot.img.zst.part"
    mv "$sdd/sd-boot.img.zst.part" "$sdd/sd-boot.img.zst"
    (cd "$sdd" && sha256sum sd-boot.img.zst > sd-boot.img.zst.sha256)
    date -Is > "$sdd/sd-boot.date"
    echo "boot medium image: $sdd/sd-boot.img.zst ($(du -h "$sdd/sd-boot.img.zst" | cut -f1))"
fi

{
    echo "recovery set, $(date -Is)"
    echo "host: $(cat /usr/lib/version), kernel $(uname -r), docker $(docker version -f '{{.Server.Version}}' 2>/dev/null)"
    echo
    echo "images:"
    for f in "$B"/images/*.tar.zst; do [ -e "$f" ] || continue; printf '  %-60s %8s  %s\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)" "$(cut -c1-19 "$f.id" 2>/dev/null)"; done
    echo
    echo "identities:"
    for c in uckp protect; do
        [ -f "$A/$c/board.info" ] && echo "  $c: $(grep -E '^board\.(shortname|sysid|serialno)=' "$A/$c/board.info" | paste -sd' ')" || true
    done
    echo
    echo "stacks (.env without secrets):"
    for e in "$A"/data/stacks/*/.env; do
        echo "  $(basename "$(dirname "$e")"): $({ grep -v -E 'PASS|SECRET|KEY' "$e" || true; } | { grep -E '_IP=|_MAC=|LAN_' || true; } | paste -sd' ')"
    done
    if [ -f "$DEST/sd-card/sd-boot.date" ]; then echo; echo "boot medium image: $(cat "$DEST/sd-card/sd-boot.date")"; fi
} > "$B/MANIFEST.txt"
(cd "$B" && find . -type f ! -name '*.id' ! -name SHA256SUMS ! -name '*.part' -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
# readable for UniFi Drive (and its cloud backup) when kept in a share
if [ -n "${OWNER:-}" ]; then chown -R "$OWNER" "$DEST"; chmod -R u+rwX,g+rwX,o-rwx "$DEST"; fi
echo "recovery set: $B ($(du -sh "$B" | cut -f1))"
SH
chmod 755 /usr/local/sbin/unas-backup

cat > /etc/systemd/system/unas-backup.service <<'UNIT'
[Unit]
Description=Recovery set of the UNAS apps
After=unas-docker.service
Requires=unas-docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/unas-backup
Nice=19
IOSchedulingClass=idle
UNIT
cat > /etc/systemd/system/unas-backup.timer <<'UNIT'
[Unit]
Description=Weekly recovery set of the UNAS apps

[Timer]
OnCalendar=Sun 01:00
Persistent=true

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
if [ "$WEEKLY" = true ]; then
    systemctl enable --now unas-backup.timer >/dev/null 2>&1
    echo "weekly run: $(systemctl show -p NextElapseUSecRealtime --value unas-backup.timer)"
fi
echo "installed: unas-backup -> $DEST"
EOF

if [[ "$run" == true ]]; then
    remote "unas-backup $([[ "$sd" == true ]] && echo --sd-image)"
fi
