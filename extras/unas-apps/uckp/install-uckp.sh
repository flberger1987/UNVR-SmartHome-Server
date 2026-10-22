#!/bin/bash
# Set up UniFi OS from the Cloud Key Gen2 Plus firmware (Network + Protect in
# one UniFi OS) as a container on the converted UNVR (run on the Mac, after
# install-on-unas.sh).
#
#   extras/unas-apps/uckp/install-uckp.sh root@<UNAS-IP> --ip <IP> \
#       [--mac 02:42:c0:a8:01:06] [--size 200G] [--up]
#
# The UNAS downloads the UCKP firmware from Ubiquiti itself, checks it against
# the pinned SHA-256 and imports the rootfs; nothing passes through Git.
#
#   <pool>/.unas-apps/uckp/           Btrfs subvolume, no copy-on-write, never in a snapshot
#       data/, persistent/            UniFi OS state (Postgres and MongoDB live in data/)
#       srv.img                       fixed-size ext4 (--size), loop-mounted on srv/ (the "HDD")
#       system.info, board.info       UCKP identity of its own (serial and MACs from --mac)
#   <pool>/.unas-apps/uckp-build/     Dockerfile and the wrappers from ../protect/
#   <pool>/.unas-apps/data/stacks/uckp/  compose.yaml, .env (shows up in Dockge)
set -Eeuo pipefail
usage="usage: $0 root@<UNAS-IP> --ip <IP> [--mac <MAC>] [--size 200G] [--rebuild] [--up]"
target=${1:?$usage}
shift
ip='' mac='02:42:c0:a8:01:06' size='200G' up=false rebuild=false
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

# UCKP firmware 6.0.11 (fw-update.ubnt.com, product unifi-cloudkey)
fw_url=https://fw-download.ubnt.com/data/unifi-cloudkey/6e30-UCKP-6.0.11-8529f9a7-63f9-4c19-be1c-d1fdd8150963.bin
fw_sha256=08d8a73e2524230a28c9f9b48c4a38fac6e4484b19aeaf9a40c468d63289a5fa
fw_version=UCKP.apq8053.v6.0.11.

volume=$(remote 'for v in /volume/*-*-*-*-*; do mountpoint -q "$v" && echo "$v" && break; done')
[[ -n "$volume" ]] || { echo 'no mounted storage pool on the UNAS' >&2; exit 1; }
apps="$volume/.unas-apps"
remote "test -x /usr/local/sbin/unas-docker-start && docker info >/dev/null" \
    || { echo 'Docker is not set up on the UNAS; run install-on-unas.sh first' >&2; exit 1; }

remote "mkdir -p '$apps/uckp-build' '$apps/data/stacks/uckp'"
remote "cat > '$apps/uckp-build/Dockerfile'" < "$here/Dockerfile"
for f in ubnt-tools ustorage; do
    remote "cat > '$apps/uckp-build/$f'" < "$here/../protect/$f"
done
remote "cat > '$apps/data/stacks/uckp/compose.yaml'" < "$here/compose.yaml"

remote "APPS='$apps' IP='$ip' MAC='$mac' SIZE='$size' REBUILD='$rebuild' FW_URL='$fw_url' FW_SHA256='$fw_sha256' FW_VERSION='$fw_version' bash -s" <<'EOF'
set -euo pipefail
P="$APPS/uckp" B="$APPS/uckp-build" S="$APPS/data/stacks/uckp"
chmod 755 "$B/ubnt-tools" "$B/ustorage"

# An existing uckp-os image (built earlier or loaded from a recovery set) is
# used as it is; --rebuild builds it again from the firmware.
if [ "$REBUILD" = true ] || ! docker image inspect uckp-os:6.0.11 >/dev/null 2>&1; then
# base image: the rootfs (one gzip squashfs inside the .bin)
if ! docker image inspect uckp-rootfs:6.0.11 >/dev/null 2>&1; then
    fw="$B/UCKP-6.0.11.bin"
    if [ ! -f "$fw" ]; then
        nice -n 19 curl -sS -f -o "$fw.part" "$FW_URL"
        echo "$FW_SHA256  $fw.part" | sha256sum -c --quiet -
        mv "$fw.part" "$fw"
    fi
    off=$(python3 - "$fw" <<'PY'
import mmap, struct, sys
f = open(sys.argv[1], 'rb')
m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
i = m.find(b'hsqs')
while i != -1:
    bsize, = struct.unpack_from('<I', m, i + 12); blog, = struct.unpack_from('<H', m, i + 22)
    major, = struct.unpack_from('<H', m, i + 28)
    if major == 4 and bsize == 1 << blog:
        print(i); break
    i = m.find(b'hsqs', i + 1)
PY
)
    [ -n "$off" ] || { echo "no squashfs found in $fw" >&2; exit 1; }
    m=/run/uckp-rootfs-ro
    mkdir -p "$m"
    mountpoint -q "$m" || mount -o loop,ro,offset="$off" -t squashfs "$fw" "$m"
    trap 'umount "$m" 2>/dev/null || true' EXIT
    grep -q "^$FW_VERSION" "$m/usr/lib/version" \
        || { echo "unexpected rootfs version $(cat "$m/usr/lib/version")" >&2; exit 1; }
    tar -C "$m" --numeric-owner -c . | docker import - uckp-rootfs:6.0.11 >/dev/null
    umount "$m"; trap - EXIT
    rm -f "$fw"   # 900 MB; downloaded again if ever needed
    echo "imported uckp-rootfs:6.0.11"
fi
(cd "$B" && DOCKER_BUILDKIT=0 docker build --network none -q -t uckp-os:6.0.11 . >/dev/null)
echo "built uckp-os:6.0.11"
else
    echo "using existing image uckp-os:6.0.11 (--rebuild to build it again)"
fi
# the stack runs uckp-os:live (deployed state incl. apps installed in UniFi OS)
if ! docker image inspect uckp-os:live >/dev/null 2>&1; then
    docker tag uckp-os:6.0.11 uckp-os:live && echo "uckp-os:live = uckp-os:6.0.11"
else
    echo "keeping uckp-os:live (to deploy a rebuild: docker tag uckp-os:6.0.11 uckp-os:live; apps installed in UniFi OS are then gone)"
fi

# storage: subvolume without CoW (excluded from pool snapshots), fixed-size ext4
[ -e "$P" ] || btrfs subvolume create "$P" >/dev/null
chattr +C "$P"
mkdir -p "$P/srv" "$P/data" "$P/persistent"
printf 'dev:    size   erasesize  name\n' > "$P/mtd"   # empty flash table, see compose.yaml
if [ ! -f "$P/srv.img" ]; then
    touch "$P/srv.img"; chattr +C "$P/srv.img"
    fallocate -l "$SIZE" "$P/srv.img"
    mkfs.ext4 -q -F -m 0 -L uckp-srv -E lazy_itable_init=1,lazy_journal_init=1 "$P/srv.img"
    fallocate -l "$SIZE" "$P/srv.img"   # mkfs discards; reserve the space again
    echo "created $SIZE volume"
fi
mountpoint -q "$P/srv" || mount -o loop,noatime "$P/srv.img" "$P/srv"

# UCKP identity: the box's board data with the Cloud Key's model ID (0xe970,
# UCK-G2-PLUS) and CPU ID (the Network app identifies its host by architecture,
# model and CPU ID), serial, MACs and a v5 board UUID (as on real
# devices; the Network app rejects other versions) derived from MAC
if [ ! -f "$P/system.info" ]; then
    hex=$(echo "$MAC" | tr -d :)
    last=$((16#${hex:10:2}))
    awk -F= -v OFS== -v s="${hex^^}" -v h="$hex" -v m0="$MAC" \
        -v m2="$(printf '%s:%02x' "${MAC%:*}" $(( (last + 1) & 255 )))" \
        -v a="${hex:0:8}-${hex:8:4}-4000-8000-$hex" '
        $1=="eth1.macaddr" {next}
        $1=="systemid" {$2="e970"}
        $1=="shortname" {$2="UCKP"}
        $1=="name" {$2="UCK-G2-PLUS"}
        $1=="serialno" || $1=="qrid" {$2=s}
        $1=="eth0.macaddr" {$2=m0}
        $1=="bt0.macaddr" {$2=m2}
        $1=="device.hashid" {$2=h}
        $1=="device.anonid" {$2=a}
        {print}' /proc/ubnthal/system.info > "$P/system.info"
    /sbin/ubnt-tools id | awk -F= -v OFS== -v s="${hex^^}" -v u="$(python3 -c 'import sys, uuid; print(uuid.uuid5(uuid.NAMESPACE_OID, sys.argv[1]))' "unvr-unas-uckp-$hex")" '
        $1=="board.sysid" {$2="0xe970"}
        $1=="board.name" {$2="UniFi Cloud Key Gen2 Plus"}
        $1=="board.shortname" {$2="UCKP"}
        $1=="board.storename" {$2="UCK-G2-PLUS"}
        $1=="board.cpu.id" {$2="410fd034-00000000"}   # Cortex-A53; the Network app matches host by CPU ID
        $1=="board.serialno" || $1=="board.qrid" {$2=s}
        $1=="board.uuid" {$2=u}
        {print}' > "$P/board.info"
    echo "wrote UCKP identity (serial ${hex^^})"
fi

printf 'UCKP_ROOT=%s\nUCKP_IP=%s\nUCKP_MAC=%s\n' "$P" "$IP" "$MAC" > "$S/.env"
EOF

if [[ "$up" == true ]]; then
    remote "cd '$apps/data/stacks/uckp' && docker compose up -d" 2>&1 | grep -v -i 'forwarding' | tail -1
    echo "UniFi OS setup: https://$ip/ (first boot takes several minutes)"
fi
