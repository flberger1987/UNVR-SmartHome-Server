#!/bin/bash
# Set up UniFi Protect (the box's own UNVR 5.1.33 userland) as a container on
# the converted UNVR (run on the Mac, after install-on-unas.sh).
#
#   extras/unas-apps/protect/install-protect.sh root@<UNAS-IP> --ip <PROTECT_IP> \
#       [--mac 02:42:c0:a8:01:05] [--size 2T] [--up]
#
# Everything is built on the UNAS from /boot/firmware/rootfs (the signed 5.1.33
# rootfs the box boots), so no Ubiquiti files pass through the Mac or Git.
#
#   <pool>/.unas-apps/protect/        Btrfs subvolume, no copy-on-write, never in a snapshot
#       srv.img                       fixed-size ext4 (--size), loop-mounted on srv/ by unas-docker
#       data/                         UniFi OS /data
#       system.info, board.info       identity of its own (serial and MACs from --mac)
#   <pool>/.unas-apps/protect-build/  Dockerfile and the two wrappers
#   <pool>/.unas-apps/data/stacks/protect/  compose.yaml, .env (shows up in Dockge)
#
# The container never gets device access: unprivileged, CAP_MKNOD dropped, and
# the UNVR storage/wipe services are masked in the image (see Dockerfile).
set -Eeuo pipefail
usage="usage: $0 root@<UNAS-IP> --ip <PROTECT_IP> [--mac <MAC>] [--size 2T] [--rebuild] [--up]"
target=${1:?$usage}
shift
ip='' mac='02:42:c0:a8:01:05' size='2T' up=false rebuild=false
while (( $# )); do
    case "$1" in
        --ip) ip=${2:?$usage}; shift ;;
        --mac) mac=${2:?$usage}; shift ;;
        --size) size=${2:?$usage}; shift ;;
        --up) up=true ;;
        --rebuild) rebuild=true ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[[ -n "$ip" ]] || { echo "$usage" >&2; exit 2; }
[[ "$mac" =~ ^02(:[0-9a-f]{2}){5}$ ]] || { echo "--mac must be a locally administered MAC (02:xx:...), lower case" >&2; exit 2; }
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

volume=$(remote 'for v in /volume/*-*-*-*-*; do mountpoint -q "$v" && echo "$v" && break; done')
[[ -n "$volume" ]] || { echo 'no mounted storage pool on the UNAS' >&2; exit 1; }
apps="$volume/.unas-apps"
remote "test -x /usr/local/sbin/unas-docker-start && docker info >/dev/null" \
    || { echo 'Docker is not set up on the UNAS; run install-on-unas.sh first' >&2; exit 1; }

remote "mkdir -p '$apps/protect-build' '$apps/data/stacks/protect'"
for f in Dockerfile ubnt-tools ustorage; do
    remote "cat > '$apps/protect-build/$f'" < "$here/$f"
done
remote "cat > '$apps/data/stacks/protect/compose.yaml'" < "$here/compose.yaml"

remote "APPS='$apps' IP='$ip' MAC='$mac' SIZE='$size' REBUILD='$rebuild' bash -s" <<'EOF'
set -euo pipefail
P="$APPS/protect" B="$APPS/protect-build" S="$APPS/data/stacks/protect"
chmod 755 "$B/ubnt-tools" "$B/ustorage"

# An existing unvr-protect image (built earlier or loaded from a recovery set)
# is used as it is; --rebuild builds it again.
if [ "$REBUILD" = true ] || ! docker image inspect unvr-protect:5.1.33 >/dev/null 2>&1; then
# base image: the 5.1.33 rootfs this box boots (squashfs on the boot medium)
if ! docker image inspect unvr-rootfs:5.1.33 >/dev/null 2>&1; then
    m=/run/unvr-rootfs-ro
    mkdir -p "$m"
    mountpoint -q "$m" || mount -o loop,ro -t squashfs /boot/firmware/rootfs "$m"
    trap 'umount "$m" 2>/dev/null || true' EXIT
    grep -q '^v5\.1\.33' "$m/usr/lib/version" \
        || { echo "boot rootfs is $(cat "$m/usr/lib/version"), expected 5.1.33" >&2; exit 1; }
    tar -C "$m" --numeric-owner -c . | docker import - unvr-rootfs:5.1.33 >/dev/null
    umount "$m"; trap - EXIT
    echo "imported unvr-rootfs:5.1.33"
fi
(cd "$B" && DOCKER_BUILDKIT=0 docker build --network none -q -t unvr-protect:5.1.33 . >/dev/null)
echo "built unvr-protect:5.1.33"
else
    echo "using existing image unvr-protect:5.1.33 (--rebuild to build it again)"
fi
docker image inspect unvr-protect:live >/dev/null 2>&1 || docker tag unvr-protect:5.1.33 unvr-protect:live

# storage: subvolume without CoW (excluded from pool snapshots), fixed-size ext4
[ -e "$P" ] || btrfs subvolume create "$P" >/dev/null
chattr +C "$P"
mkdir -p "$P/srv" "$P/data"
if [ ! -f "$P/srv.img" ]; then
    touch "$P/srv.img"; chattr +C "$P/srv.img"
    fallocate -l "$SIZE" "$P/srv.img"
    mkfs.ext4 -q -F -m 0 -L protect-srv -E lazy_itable_init=1,lazy_journal_init=1 "$P/srv.img"
    fallocate -l "$SIZE" "$P/srv.img"   # mkfs discards; reserve the space again
    echo "created $SIZE Protect volume"
fi
mountpoint -q "$P/srv" || mount -o loop,noatime "$P/srv.img" "$P/srv"

# identity of its own: UNVR board data with serial, MACs and a v5 board UUID
# (as on real devices) derived from MAC
if [ ! -f "$P/system.info" ]; then
    hex=$(echo "$MAC" | tr -d :)
    last=$((16#${hex:10:2}))
    mac_n() { printf '%s:%02x' "${MAC%:*}" $(( (last + $1) & 255 )); }
    awk -F= -v OFS== -v s="${hex^^}" -v h="$hex" -v m0="$MAC" -v m1="$(mac_n 1)" -v m2="$(mac_n 2)" \
        -v a="${hex:0:8}-${hex:8:4}-4000-8000-$hex" '
        $1=="serialno" || $1=="qrid" {$2=s}
        $1=="eth0.macaddr" {$2=m0}
        $1=="eth1.macaddr" {$2=m1}
        $1=="bt0.macaddr" {$2=m2}
        $1=="device.hashid" {$2=h}
        $1=="device.anonid" {$2=a}
        {print}' /proc/ubnthal/system.info > "$P/system.info"
    /sbin/ubnt-tools id | awk -F= -v OFS== -v s="${hex^^}" -v u="$(python3 -c 'import sys, uuid; print(uuid.uuid5(uuid.NAMESPACE_OID, sys.argv[1]))' "unvr-unas-protect-$hex")" '
        $1=="board.serialno" || $1=="board.qrid" {$2=s}
        $1=="board.uuid" {$2=u}
        {print}' > "$P/board.info"
    echo "wrote identity files (serial ${hex^^})"
fi

printf 'PROTECT_ROOT=%s\nPROTECT_IP=%s\nPROTECT_MAC=%s\n' "$P" "$IP" "$MAC" > "$S/.env"
EOF

if [[ "$up" == true ]]; then
    remote "cd '$apps/data/stacks/protect' && docker compose up -d" 2>&1 | grep -v -i 'forwarding' | tail -1
    echo "UniFi OS setup: https://$ip/ (first boot takes a few minutes)"
fi
