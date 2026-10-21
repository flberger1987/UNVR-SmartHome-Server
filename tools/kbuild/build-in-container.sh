#!/bin/bash
# Rebuild the UNVR 5.1.33 btrfs/fuse/zstd_compress modules the way the
# converter's on-device chroot does, inside a Debian bullseye arm64 container.
set -Eeuo pipefail
export LC_ALL=C DEBIAN_FRONTEND=noninteractive
start=$(date +%s)
stamp() { printf '[%4ss] %s\n' "$(( $(date +%s) - start ))" "$*"; }

snapshot=http://snapshot.debian.org/archive/debian/20240901T000000Z
printf 'deb %s bullseye main\n' "$snapshot" > /etc/apt/sources.list
rm -f /etc/apt/sources.list.d/*
stamp 'installing pinned bullseye toolchain'
apt-get -o Acquire::Check-Valid-Until=false -qq update
apt-get -o Acquire::Check-Valid-Until=false -qq install -y --no-install-recommends \
    build-essential bc bison flex libssl-dev libelf-dev kmod xz-utils curl ca-certificates >/dev/null
test "$(dpkg-query -W -f='${Version}' gcc-10)" = 10.2.1-6
stamp "gcc-10 $(dpkg-query -W -f='${Version}' gcc-10), binutils $(dpkg-query -W -f='${Version}' binutils)"

cd /usr/src
stamp 'downloading linux-4.19.152 from kernel.org'
curl -fsSL --proto '=https' -o linux-4.19.152.tar.xz https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.19.152.tar.xz
echo 'a5a6aa9c2c2810efa72b5d9723de86ccea3f965b2dd748d15e82d5fac23a055d  linux-4.19.152.tar.xz' | sha256sum -c --quiet
tar -xJf linux-4.19.152.tar.xz
rm -f linux-4.19.152.tar.xz
cd linux-4.19.152

cp /out/config .config
sed -i 's/^CONFIG_LOCALVERSION=""$/CONFIG_LOCALVERSION="-alpine-unvr"/' .config
sed -i -e 's/^# CONFIG_BTRFS_FS is not set$/CONFIG_BTRFS_FS=m/' -e 's/^# CONFIG_FUSE_FS is not set$/CONFIG_FUSE_FS=m/' .config
grep -qx 'CONFIG_BTRFS_FS=m' .config
grep -qx 'CONFIG_FUSE_FS=m' .config

stamp 'compiling (same commands as on the UNVR)'
make -s olddefconfig
grep -qx 'CONFIG_ZSTD_COMPRESS=m' .config
test "$(make -s kernelrelease)" = 4.19.152-alpine-unvr
jobs=${JOBS:-2}
make -s -j"$jobs" prepare modules_prepare
make -s -j"$jobs" M=lib/zstd modules
make -s -j"$jobs" M=fs/btrfs modules
make -s -j"$jobs" M=fs/fuse modules
stamp 'compile finished'

check() {
    local file=$1 want=$2 have
    have=$(sha256sum "$file" | cut -d' ' -f1)
    if [[ "$have" == "$want" ]]; then echo "IDENTICAL  ${file##*/}"; else echo "DIFFERENT  ${file##*/} $have"; fi
    cp "$file" /out/
}
check lib/zstd/zstd_compress.ko a05acb0c06dde88c1cf1b00759437a7cb338faa3e361fd946119b9dc49531043
check fs/btrfs/btrfs.ko f9ae62b75113ad4291d1bd905e74c0749dea04e5dff79782b43c3d24a8badd9d
check fs/fuse/fuse.ko b2d5296f516e8e2bcbf8f55d67790a930746984c9eec7c2ab6d2aa578fa142ab
# Second pass, after the pinned modules: macvlan for containers with their own
# LAN address. Only CONFIG_MACVLAN changes, so the pinned modules stay untouched.
stamp 'building extra module macvlan'
sed -i 's/^# CONFIG_MACVLAN is not set$/CONFIG_MACVLAN=m/' .config
make -s olddefconfig
grep -qx 'CONFIG_MACVLAN=m' .config
make -s -j"$jobs" modules_prepare
make -s -j"$jobs" M=drivers/net modules 2>&1 | grep -v -E 'Module.symvers|no dependencies' || true
cp drivers/net/macvlan.ko /out/
echo "BUILT      macvlan.ko $(sha256sum drivers/net/macvlan.ko | cut -d' ' -f1)"
stamp done
