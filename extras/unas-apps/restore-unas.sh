#!/bin/bash
# Bring the apps back from a recovery set made by backup-unas.sh (run on the Mac).
#
#   extras/unas-apps/restore-unas.sh root@<UNAS-IP> [--set <dir on the UNAS>]
#
# Order (docs/RECOVERY.md): converted UNAS with a storage pool, host tuning,
# install-on-unas.sh (Docker), then this script, then install-uckp.sh /
# install-protect.sh (they keep the restored identity and use the loaded
# image) and install-on-unas.sh --up.
#
# Default set: <pool>/.unas-apps/backup/recovery. After rebuilding the pool,
# copy the set back to that place first. Existing files are never overwritten.
set -Eeuo pipefail
usage="usage: $0 root@<UNAS-IP> [--set <dir on the UNAS>]"
target=${1:?$usage}
shift
set_dir=''
while (( $# )); do
    case "$1" in
        --set) set_dir=${2:?$usage}; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

remote "SET='$set_dir' bash -s" <<'EOF'
set -euo pipefail
volume=$(for v in /volume/*-*-*-*-*; do mountpoint -q "$v" && echo "$v" && break; done)
[ -n "$volume" ] || { echo 'no mounted storage pool; create one in UniFi Drive first' >&2; exit 1; }
A="$volume/.unas-apps"
B=${SET:-$A/backup/recovery}
[ -f "$B/SHA256SUMS" ] || { echo "no recovery set in $B" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo 'Docker is not running; run install-on-unas.sh first' >&2; exit 1; }

echo "checking $B"
(cd "$B" && sha256sum -c --quiet SHA256SUMS)

# The UniFi OS containers' directories are Btrfs subvolumes without
# copy-on-write (outside pool snapshots); create them before unpacking into them.
list=$(zstd -dc "$B/config.tar.zst" | tar -t)
for c in uckp protect; do
    if grep -q "^$c/" <<< "$list"; then
        [ -e "$A/$c" ] || { btrfs subvolume create "$A/$c" >/dev/null; chattr +C "$A/$c"; }
    fi
done
# configuration and identities; existing files stay as they are
zstd -dc "$B/config.tar.zst" | tar -C "$A" -xp --skip-old-files
echo "configuration restored (existing files kept)"

for f in "$B"/images/*.tar.zst; do
    echo "loading $(basename "$f")"
    zstd -dc "$f" | docker load -q
done
# live states of the UniFi OS containers (installed apps) under the stack's image name
for live in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -- '-live$'); do
    docker tag "$live" "${live%-live}"
    echo "${live%-live} = $live"
done

# LoxBerry's volume, if it is new or empty
if [ -f "$B/loxberry-volume.tar.zst" ]; then
    docker volume inspect unas-apps_loxberry >/dev/null 2>&1 || \
        docker volume create --label com.docker.compose.project=unas-apps \
            --label com.docker.compose.volume=loxberry unas-apps_loxberry >/dev/null
    lv=$(docker volume inspect -f '{{.Mountpoint}}' unas-apps_loxberry)
    if [ -z "$(ls -A "$lv")" ]; then
        zstd -dc "$B/loxberry-volume.tar.zst" | tar -C "$lv" -xp
        echo "LoxBerry volume restored"
    else
        echo "LoxBerry volume not empty, left as it is"
    fi
fi

echo
echo "Network backups in $B/network (restore one in the Network app if its data is new):"
ls -1t "$B"/network/*.unf 2>/dev/null | head -3 || true
EOF

cat <<'TXT'

Next:
  extras/unas-apps/uckp/install-uckp.sh <target> --ip <UCKP_IP> --mac <UCKP_MAC> --size <SIZE>
  extras/unas-apps/install-on-unas.sh <target> --up
(identity files and images from the set are kept; see docs/RECOVERY.md)
TXT
