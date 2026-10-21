#!/bin/bash
# Remote phase engine for unvr_unas_installer_macos.sh.
# This file is streamed over SSH; run the macOS orchestrator, not this file.

set -Eeuo pipefail
export LC_ALL=C
umask 077

readonly INSTALLER_VERSION=2
readonly PAYLOAD_VERSION=22
readonly DEBIAN_DRIVE_CLOSURE_SHA256=52e38d9730228dc2e6632cccbcd777498450d2b79f0ebf1077fa34dec8d197f9
readonly DEBIAN_KBUILD_CLOSURE_SHA256=fb99e5bfe01f99d9f40f613e7610ec34c77a1c67c0264f74b26cc455487471f8
readonly UBIQUITI_DRIVE_PACKAGES_SHA256=8fdfe83b30b934cc5b00b21a9a9ec812901ac979ffd65b9985b0fd012bf31067
readonly STATE_ROOT=/data/unvr-unas-installer
readonly RUNTIME_ROOT=/data/unvr-unas-runtime
readonly KBUILD_ROOT=/var/log/unvr-kbuild-root
readonly BACKUP_LINK="$STATE_ROOT/backup-dir"
readonly EXPECTED_OS=4.1.22
readonly EXPECTED_KERNEL=4.19.152-alpine-unvr
readonly EXPECTED_ARCH=arm64
readonly EXPECTED_OS_5=UNVR4.al324.v5.1.33.44ce47b.260909.0025
readonly NORMALIZATION_IMAGE=/mnt/.rwfs/unvr-unas-firmware/UNVR-5.1.33.bin
readonly NORMALIZATION_IMAGE_URL=https://fw-download.ubnt.com/data/unifi-nvr/976a-UNVR-5.1.33-84c520f3-fb97-41e0-be2b-b0f89c46c7b8.bin
readonly NORMALIZATION_IMAGE_SIZE=787559347
readonly NORMALIZATION_IMAGE_SHA256=b170e97f9b7a703947380aed1108221e70ab18074b986906aca9df10891ca1e0
readonly UPDATE_5_1_33_PHYSICAL=UNVR4.al324.v5.1.33.44ce47b.260909.0025
readonly EXPECTED_CORE_5_VERSION=5.1.132
readonly EXPECTED_PROTECT_5_VERSION=7.1.87
readonly EXPECTED_USTD_5_VERSION=5.1.18-10+g8a41ccbc679d
readonly EXPECTED_UBNTNAS_5_VERSION=1.0.0-10+g27d234f8e526
readonly EXPECTED_UBNT_TOOLS_5_VERSION=5.1.11~556+g3abf3fe
readonly EXPECTED_HAL_5_VERSION=1.0.0-1378+ga49db765b339
readonly EXPECTED_ULP_5_VERSION=1.13.11+6130
readonly EXPECTED_SAMBA_5_VERSION=2:4.13.13+dfsg-1~deb11u8
readonly EXPECTED_BTRFS_PROGS_VERSION=5.10.1-2
readonly EXPECTED_NFS_VERSION=1:1.3.4-6+deb11u1
readonly EXPECTED_FUSE3_VERSION=3.10.3-2
readonly EXPECTED_LVM2_VERSION=2.03.11-2.1
readonly EXPECTED_DM_EVENT_VERSION=2:1.02.175-2.1
readonly EXPECTED_THIN_PROVISIONING_VERSION=0.9.0-1
readonly EXPECTED_LIBAIO_VERSION=0.3.112-9
readonly STOCK_UNAS_VALID_UNTIL_SHA256=92dd8add3f0093b490c4d4c57f6a2bc7afc1a7519b078b8034db2df5add7f458
readonly EXPECTED_LVM_EXEC_HASH=d61b5933ae9e91f087eaa6941354b072ee23140477418de3996e3593bebd8570
readonly CORE_5_STOCK_HASH=9def42c03b368a9434b1b3d5ee48f7a295bae616ae1060639f4c53c4e292fbb0
readonly CORE_5_UNAS_HASH=a65c0736fd0abad3df5cc4cd1a42549cacc84e1b76f07ff30eff5cd1d75a774b
readonly PREVIOUS_CORE_5_UNAS_HASH=58416ef26d535c7c618b341ae92e7445d10a74e9e0809e9122ad2b78326dd90c
readonly EXPECTED_CORE_VERSION=4.1.140-pre+fcd.1
readonly EXPECTED_PROTECT_VERSION=5.3.45
readonly EXPECTED_USTD_VERSION=4.1.2-10+gc4588538951d
readonly EXPECTED_UBNTNAS_VERSION=1.0.0-10+gf6346cbdf0b1
readonly EXPECTED_UBNT_TOOLS_VERSION=4.1.27~505+g5f31d5d
readonly EXPECTED_HAL_VERSION=1.0.0-10+g0b56f5691f9b
readonly EXPECTED_ROOTFS_HASH=7d07e789e5638a4d6d5e0031741166b210208df0b65676842e506614439248eb
readonly EXPECTED_KERNEL_PART_HASH=9b1021e69fee9834bdfb84195a047c90aff568ce4c471ab04b757d0bf5e5dfe1
readonly EXPECTED_DTB_HASH=508b402774e14e66d3a692f3593ad804f9425eece7bd287617189d19c281f222
readonly EXPECTED_KCONFIG_HASH=b5343c5b9345f18e9c1c3841f2e71db99677a99215ea1f975ce3c3132d7bcbeb
readonly CORE_ORIGINAL_HASH=1bc2a7b098f5042b479b5739cc2a4bf69220a3188cb35cae5c21adaf4050bf5c
readonly CORE_PATCHED_HASH=f89f57e204ea53024b604b3acbd277fcac03605e7c41ff5d434b433d72f971aa
readonly CORE_IDENTITY_HASH=1b77e7c957fbcf3a077f9fc45f41fd0ffb80203750ce7b6249c5ee9ef3692dbb
readonly DRIVE_ORIGINAL_HASH=1d20ad224041781f0574abdbb05bc0ccb309febe8b6cc385d8cdd62bb854573e
readonly DRIVE_FINAL_HASH=1625e66e6f66bae32e1348ec3a1be33761719a2b4bc500ac6cd8ca1bdf934087
readonly ZSTD_MODULE_HASH=a05acb0c06dde88c1cf1b00759437a7cb338faa3e361fd946119b9dc49531043
readonly BTRFS_MODULE_HASH=f9ae62b75113ad4291d1bd905e74c0749dea04e5dff79782b43c3d24a8badd9d
readonly FUSE_MODULE_HASH=b2d5296f516e8e2bcbf8f55d67790a930746984c9eec7c2ab6d2aa578fa142ab
readonly KERNEL_TARBALL_HASH=a5a6aa9c2c2810efa72b5d9723de86ccea3f965b2dd748d15e82d5fac23a055d
readonly KERNEL_TARBALL_URL=https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.19.152.tar.xz
readonly KBUILD_DEBIAN_SNAPSHOT=https://snapshot.debian.org/archive/debian/20240901T000000Z
readonly WSDD_VERSION=2:0.7.0-1~0mag0-3+g7eb6b8a384b
readonly WSDD_EXEC_HASH=7b3a54cbad2f9d2ba97d099defbe28946721355a0b965e8d945426e8c26a3251

log() { printf '[unvr-unas] %s\n' "$*"; }
die() { printf '[unvr-unas] ERROR: %s\n' "$*" >&2; exit 1; }
sha() { sha256sum "$1" | awk '{print $1}'; }
phase_done() {
    local marker="$STATE_ROOT/phases/$1.done" content
    [[ -f "$marker" && ! -L "$marker" ]] || return 1
    content=$(cat "$marker")
    [[ -z "$content" || "$content" == "$INSTALLER_VERSION" ]] \
        || die "invalid completed phase marker: $1"
}
mark_done() {
    local phase=$1 target tmp
    [[ "$phase" =~ ^[a-z0-9-]+$ ]] || die 'invalid phase marker name'
    [[ -d "$STATE_ROOT/phases" && ! -L "$STATE_ROOT/phases" ]] \
        || die 'installer phase directory is invalid'
    sync
    target="$STATE_ROOT/phases/$phase.done"
    tmp=$(mktemp "$STATE_ROOT/phases/.$phase.done.XXXXXX")
    trap 'rm -f -- "$tmp"' RETURN EXIT HUP INT TERM
    printf '%s\n' "$INSTALLER_VERSION" > "$tmp"
    chmod 600 "$tmp"
    sync "$tmp"
    mv -f "$tmp" "$target"
    sync "$target"
    trap - RETURN EXIT HUP INT TERM
}
require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die 'remote command must run as root'; }
pkg_version() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true; }
pkg_configured() { [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null || true)" == 'install ok installed' ]]; }
require_eq() { [[ "$1" == "$2" ]] || die "$3"; }
# Factory recovery kernels seen on four-bay UNVRs. The recovery partition is
# only read, never written; 99798c... is the 4.1.37-ubnt @ 20201214 build.
require_known_recovery_kernel() {
    case "$(sha /dev/mtd5)" in
        dadcfc457787621b42e7eeb9266810a5e8ae1c329d4402d2793fb508943794e9|\
        99798c2755f72343e75915365f3e9a074379b12b28e058b3c2182af416adcc5c) ;;
        *) die "$1" ;;
    esac
}
require_free_bytes() {
    local path=$1 required=$2 label=$3 available
    available=$(df -B1 --output=avail "$path" | tail -n1 | tr -d ' ')
    [[ "$available" =~ ^[0-9]+$ && "$available" -ge "$required" ]] \
        || die "insufficient free space for $label"
}
assert_mtd_layout() {
    local index expected_size expected_name
    while IFS='|' read -r index expected_size expected_name; do
        [[ -r "/sys/class/mtd/mtd$index/size" && -r "/sys/class/mtd/mtd$index/name" && -r "/dev/mtd$index" ]] \
            || die "required MTD partition is missing: mtd$index"
        require_eq "$(cat "/sys/class/mtd/mtd$index/size")" "$expected_size" "MTD partition size mismatch: mtd$index"
        require_eq "$(cat "/sys/class/mtd/mtd$index/name")" "$expected_name" "MTD partition name mismatch: mtd$index"
    done <<'EOF'
0|1835008|u-boot
1|65536|u-boot env
2|65536|u-boot env redundant
3|65536|Factory
4|65536|EEPROM
5|16777216|recovery kernel
6|14680064|config
EOF
}

validate_normalization_bootloader() {
    local physical_version=$1 source_uboot
    source_uboot=$(sha /dev/mtd0)
    case "$source_uboot" in
        6006a0aae68b096e44973eae9b57e44add48d894d06c95c4702c21e0b0dfb762|\
        b8e936e52355819bb113c165f3b29e635ac9d821d03e7921159aad43690e719f) ;;
        95ab38b870eb3886f35a6411244f99596d9788e165c84b8ff3b6e522b3d5f2a6)
            # A stock reset retains the OS and its bootloader. The signed
            # Source and destination checks both bind this bootloader to
            # the exact signed UNVR 5.1.33 rootfs and kernel configuration.
            require_eq "$physical_version" "$UPDATE_5_1_33_PHYSICAL" \
                '5.1.33 U-Boot requires the exact signed UNVR 5.1.33 source'
            require_eq "$(sha /boot/firmware/rootfs)" \
                e29dd4200a24106a8aadefc6122a145c2510570f39173b993bf595bde9a75944 \
                'UNVR 5.1.33 source rootfs hash mismatch'
            require_eq "$(zcat /proc/config.gz | sha256sum | awk '{print $1}')" \
                6e7bcbc5c1779103dfadcf7b49a1c3e50e49c647bb0284ff478781e0888b3f6c \
                'UNVR 5.1.33 source kernel configuration mismatch'
            ;;
        *) die "source U-Boot is not a validated official UNVR version (firmware=$physical_version sha256=$source_uboot)" ;;
    esac
    require_known_recovery_kernel 'source recovery kernel mismatch'
}
dump_postgres_database() {
    local database=$1 destination=$2
    [[ -d "$(dirname "$destination")" ]] || die "database backup directory is missing: $destination"
    sudo -u postgres sh -c 'cd /tmp && exec pg_dump -Fc "$1"' sh "$database" \
        | tee "$destination" >/dev/null
    chmod 600 "$destination"
    pg_restore -l "$destination" >/dev/null
}

assert_base_5_physical() {
    require_root
    require_eq "$(dpkg --print-architecture)" "$EXPECTED_ARCH" 'unsupported architecture'
    require_eq "$(uname -r)" "$EXPECTED_KERNEL" 'unsupported kernel'
    require_eq "$(cat /usr/lib/version 2>/dev/null || true)" "$EXPECTED_OS_5" 'unsupported UniFi OS 5.x baseline'
    require_eq "$(sed -n 's/^shortname=//p' /proc/ubnthal/system.info | head -n1)" UNVR4 'target is not a four-bay UNVR'
    require_eq "$(blockdev --getsize64 /dev/boot)" 31268536320 'internal boot-medium geometry mismatch'
    assert_mtd_layout
    require_eq "$(sha /dev/mtd0)" 95ab38b870eb3886f35a6411244f99596d9788e165c84b8ff3b6e522b3d5f2a6 'UNVR 5.1 U-Boot mismatch'
    require_known_recovery_kernel 'recovery kernel mismatch'
    require_eq "$(pkg_version unifi-core)" "$EXPECTED_CORE_5_VERSION" 'unifi-core 5.x version mismatch'
    require_eq "$(pkg_version ustd:arm64)" "$EXPECTED_USTD_5_VERSION" 'ustd 5.x version mismatch'
    require_eq "$(pkg_version ubntnas)" "$EXPECTED_UBNTNAS_5_VERSION" 'ubntnas 5.x version mismatch'
    require_eq "$(pkg_version ubnt-tools)" "$EXPECTED_UBNT_TOOLS_5_VERSION" 'ubnt-tools 5.x version mismatch'
    require_eq "$(pkg_version unifi-hal:arm64)" "$EXPECTED_HAL_5_VERSION" 'unifi-hal 5.x version mismatch'
    require_eq "$(pkg_version ulp-go)" "$EXPECTED_ULP_5_VERSION" 'ULP 5.x version mismatch'
    require_eq "$(pkg_version unifi-protect)" "$EXPECTED_PROTECT_5_VERSION" 'UniFi Protect 5.x version mismatch'
    require_eq "$(pkg_version uos)" 5.1.5 'UOS 5.1.33 utility version mismatch'
    require_eq "$(pkg_version node24)" 24.8.0 'node24 version mismatch'
    require_eq "$(sha /boot/firmware/rootfs)" e29dd4200a24106a8aadefc6122a145c2510570f39173b993bf595bde9a75944 'UNVR 5.1 rootfs hash mismatch'
    require_eq "$(zcat /proc/config.gz | sha256sum | awk '{print $1}')" 6e7bcbc5c1779103dfadcf7b49a1c3e50e49c647bb0284ff478781e0888b3f6c 'UNVR 5.1 kernel config mismatch'
}

assert_base_5_clean() {
    assert_base_5_physical
    require_eq "$(sha /usr/share/unifi-core/app/service.js)" "$CORE_5_STOCK_HASH" 'stock Core 5.1 bundle mismatch'
    require_eq "$(sha /usr/lib/uid-agent/unifi-os-consoles.json)" a7db66c52b418eb39bc2f66f5fc73f5a55083237863ffec50f921ecf303dbe35 'stock UID asset mismatch'
    require_eq "$(sha /usr/lib/ulp-go/unifi-os-console.json)" 4accb0af048a5a52deb9ff0c60a0fb98c72d9a4efd0fa7e48721117f94bdad1b 'stock ULP asset mismatch'
    require_eq "$(sha /usr/share/unifi-assets/manifest.json)" 4bf51b9f1f8f04350e8401b7898112bd69f723b14a84a1fd30b04d805dd54f20 'stock UNVR asset manifest mismatch'
    [[ -z "$(pkg_version unifi-drive)" ]] || die 'clean UNVR 5.1 baseline already has Drive installed'
}

assert_base_5_runtime() {
    assert_base_5_physical
    case "$(sha /usr/share/unifi-core/app/service.js)" in
        "$CORE_5_STOCK_HASH"|"$CORE_5_UNAS_HASH"|"$PREVIOUS_CORE_5_UNAS_HASH") ;;
        *) die 'Core 5.1 bundle is neither stock nor the validated UNAS profile' ;;
    esac
}

assert_supported_base() {
    case "$(cat /usr/lib/version 2>/dev/null || true)" in
        UNVR4.al324.v4.1.22.47ca036.250414.1648) assert_base ;;
        "$EXPECTED_OS_5") assert_base_5_runtime ;;
        *) die 'unsupported physical UNVR baseline' ;;
    esac
}

assert_base() {
    require_root
    require_eq "$(dpkg --print-architecture)" "$EXPECTED_ARCH" 'unsupported architecture'
    require_eq "$(uname -r)" "$EXPECTED_KERNEL" 'unsupported kernel'
    require_eq "$(ubntnas version 2>/dev/null | tail -n1)" "$EXPECTED_OS" 'unsupported UniFi OS'
    require_eq "$(sed -n 's/^shortname=//p' /proc/ubnthal/system.info | head -n1)" UNVR4 'target is not a four-bay UNVR'
    require_eq "$(pkg_version unifi-core)" "$EXPECTED_CORE_VERSION" 'unifi-core version mismatch'
    require_eq "$(pkg_version ustd:arm64)" "$EXPECTED_USTD_VERSION" 'ustd version mismatch'
    require_eq "$(pkg_version ubntnas)" "$EXPECTED_UBNTNAS_VERSION" 'ubntnas version mismatch'
    require_eq "$(pkg_version ubnt-tools)" "$EXPECTED_UBNT_TOOLS_VERSION" 'ubnt-tools version mismatch'
    require_eq "$(pkg_version unifi-hal:arm64)" "$EXPECTED_HAL_VERSION" 'unifi-hal version mismatch'
    require_eq "$(pkg_version unifi-protect)" "$EXPECTED_PROTECT_VERSION" 'UniFi Protect version mismatch'
    require_eq "$(pkg_version node18)" 18.18.2 'node18 version mismatch'
    [[ -x /usr/bin/node18 ]] || die 'validated node18 executable is missing'
    require_eq "$(sha /boot/firmware/rootfs)" "$EXPECTED_ROOTFS_HASH" 'running firmware rootfs hash mismatch'
    require_eq "$(sha /dev/boot1)" "$EXPECTED_KERNEL_PART_HASH" 'kernel partition hash mismatch'
    require_eq "$(sha /sys/firmware/fdt)" "$EXPECTED_DTB_HASH" 'running device-tree hash mismatch'
    require_eq "$(zcat /proc/config.gz | sha256sum | awk '{print $1}')" "$EXPECTED_KCONFIG_HASH" 'running kernel config hash mismatch'
    case "$(sha /usr/share/unifi-core/app/service.js)" in
        "$CORE_ORIGINAL_HASH"|"$CORE_PATCHED_HASH"|"$CORE_IDENTITY_HASH") ;;
        *) die 'unifi-core service bundle is neither the validated original nor patch' ;;
    esac
}

preflight() {
    assert_base
    [[ -b /dev/boot && -b /dev/boot1 ]] || die 'expected internal boot medium is absent'
    [[ $(blockdev --getsize64 /dev/boot) == 31268536320 ]] || die 'internal boot-medium geometry mismatch'
    systemctl is-active --quiet usd.service || die 'usd is not active'
    systemctl is-active --quiet uhwd.service || die 'uhwd is not active'
    [[ -s /etc/ustd/storage.conf ]] || die 'USTD storage configuration missing'
    log 'preflight passed: exact UNVR 4.1.22 baseline'
}

detect_baseline_cmd() {
    require_root
    case "$(cat /usr/lib/version 2>/dev/null || true)" in
        "$EXPECTED_OS_5") printf 'BASELINE=5.1.33\n' ;;
        UNVR4.al324.v*) printf 'BASELINE=normalization-required\n' ;;
        *) printf 'BASELINE=unsupported\n'; exit 2 ;;
    esac
}

factory_reset_preflight_cmd() {
    require_root
    local physical count=0 name
    physical=$(cat /usr/lib/version 2>/dev/null || true)
    [[ "$physical" == UNVR4.al324.v* ]] || die 'factory reset target is not running four-bay UNVR firmware'
    require_eq "$(dpkg --print-architecture)" "$EXPECTED_ARCH" 'factory reset target architecture mismatch'
    require_eq "$(uname -r)" "$EXPECTED_KERNEL" 'factory reset target kernel mismatch'
    require_eq "$(sed -n 's/^shortname=//p' /proc/ubnthal/system.info | head -n1)" UNVR4 \
        'factory reset target is not the physical four-bay UNVR'
    [[ -b /dev/boot && -b /dev/boot1 ]] || die 'factory reset target internal boot medium is missing'
    require_eq "$(blockdev --getsize64 /dev/boot)" 31268536320 'factory reset target boot-medium geometry mismatch'
    assert_mtd_layout
    validate_normalization_bootloader "$physical"
    [[ -x /sbin/ubnt-systool && -f /sbin/ubnt-systool && ! -L /sbin/ubnt-systool ]] \
        || die 'stock Ubiquiti reset utility is missing or unsafe'
    grep -q 'reset2defaults \[--do-format\]' /sbin/ubnt-systool \
        || die 'stock Ubiquiti reset utility does not expose the validated format option'
    [[ ! -e /var/run/fwupdate.pid && ! -e /boot/firmware/rootfs.new ]] \
        || die 'factory reset is blocked by an incomplete firmware update'
    ! pgrep -x fwupdate >/dev/null 2>&1 || die 'factory reset is blocked by an active firmware updater'
    for name in sda sdb sdc sdd; do
        [[ ! -b "/dev/$name" ]] || {
            require_eq "$(cat "/sys/class/block/$name/removable")" 0 "$name unexpectedly resolves to removable media"
            count=$((count + 1))
        }
    done
    printf 'RESET_TARGET=UNVR4\n'
    printf 'SATA_DRIVE_COUNT=%s\n' "$count"
    printf 'RESET_ACTION=console-config-and-all-installed-external-storage\n'
}

factory_network_association_cmd() {
    require_root
    local target_ip=${1:-} interface gateway client_mac
    [[ "$target_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || die 'target IPv4 address is required for Network-controller discovery'
    interface=$(ip -o -4 address show scope global \
        | awk -v target="$target_ip" '$4 ~ ("^" target "/") {print $2; exit}')
    [[ "$interface" =~ ^[A-Za-z0-9_.:-]+$ ]] \
        || die 'could not identify the interface carrying the UNVR address'
    [[ -r "/sys/class/net/$interface/address" ]] \
        || die 'could not read the UNVR client address for controller cleanup'
    client_mac=$(cat "/sys/class/net/$interface/address")
    [[ "$client_mac" =~ ^[0-9a-f]{2}(:[0-9a-f]{2}){5}$ ]] \
        || die 'UNVR client address is malformed'
    gateway=$(ip -4 route show default dev "$interface" \
        | awk '$1 == "default" && $2 == "via" {print $3; exit}')
    [[ "$gateway" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || die 'could not identify the UNVR default gateway'
    printf 'CLIENT_MAC=%s\n' "$client_mac"
    printf 'GATEWAY_IP=%s\n' "$gateway"
}

factory_cloud_unregister_cmd() {
    require_root
    local system owner auth token csrf status header_file deadline
    system=$(curl -ksSf --max-time 10 https://127.0.0.1/api/system 2>/dev/null || true)
    if jq -e '.cloudConnected == false and .remoteAccessEnabled == false' \
        <<<"$system" >/dev/null 2>&1; then
        printf 'CLOUD_UNREGISTERED=already\n'
        return
    fi
    # A console that was in use can have several users; only the Owner may
    # unregister it from Site Manager, so prefer the user holding that role.
    owner=$(sudo -u postgres psql -X -d ulp-go -A -t \
        -c "SELECT u.unique_id FROM \"user\" u JOIN role_user ru ON ru.user_id = u.unique_id JOIN role r ON r.unique_id = ru.role_id WHERE u.deleted_at IS NULL AND r.system_key = 'owner' ORDER BY u.created_at LIMIT 1" 2>/dev/null || true)
    if [[ -z "$owner" ]]; then
        owner=$(sudo -u postgres psql -X -d ulp-go -A -t \
            -c 'SELECT unique_id FROM "user" WHERE deleted_at IS NULL LIMIT 1' 2>/dev/null || true)
    fi
    [[ -n "$owner" ]] || die 'current console owner is unavailable for cloud unregistration'
    auth=$(jq -nc --arg owner "$owner" '{userId:$owner,expiresInSec:120}' \
        | curl -fsS --max-time 5 -H 'Content-Type: application/json' -d @- \
            http://127.0.0.1:11081/api/authToken) \
        || die 'could not create the scoped local cloud-unregistration token'
    token=$(jq -er .token <<<"$auth") || die 'scoped local token is missing'
    csrf=$(jq -er .csrfToken <<<"$auth") || die 'scoped local CSRF token is missing'
    header_file=$(mktemp /run/unvr-unas-cloud-unregister.XXXXXX)
    trap 'rm -f -- "${header_file:-}"' RETURN EXIT HUP INT TERM
    printf 'X-CSRF-Token: %s\nCookie: TOKEN=%s\n' "$csrf" "$token" > "$header_file"
    chmod 0600 "$header_file"
    status=$(curl -ksS --max-time 45 -o /dev/null -w '%{http_code}' \
        -H 'Content-Type: application/json' -H "@$header_file" \
        -d '{}' https://127.0.0.1/api/cloud/unregister || true)
    jq -nc --arg token "$token" '{token:$token}' \
        | curl -fsS --max-time 5 -X DELETE -H 'Content-Type: application/json' -d @- \
            http://127.0.0.1:11081/api/authToken >/dev/null 2>&1 || true
    token=
    csrf=
    auth=
    rm -f -- "$header_file"
    trap - RETURN EXIT HUP INT TERM
    case "$status" in 200|204) ;; *) die "Core cloud unregister returned HTTP $status" ;; esac
    deadline=$((SECONDS + 90))
    while (( SECONDS < deadline )); do
        system=$(curl -ksSf --max-time 10 https://127.0.0.1/api/system 2>/dev/null || true)
        if jq -e '.cloudConnected == false and .remoteAccessEnabled == false' \
            <<<"$system" >/dev/null 2>&1; then
            printf 'CLOUD_UNREGISTERED=now\n'
            return
        fi
        sleep 2
    done
    die 'console did not confirm cloud unregistration'
}

factory_reset_wipe_cmd() {
    factory_reset_preflight_cmd >/dev/null
    sync
    exec /sbin/ubnt-systool reset2defaults ucore --do-format
}

normalization_source_preflight() {
    require_root
    local physical_version
    physical_version=$(cat /usr/lib/version 2>/dev/null || true)
    [[ "$physical_version" == UNVR4.al324.v* ]] || die 'source firmware is not a four-bay UNVR image'
    [[ "$physical_version" != "$EXPECTED_OS_5" ]] || die 'source is already the exact 5.1.33 baseline'
    require_eq "$(dpkg --print-architecture)" "$EXPECTED_ARCH" 'unsupported architecture'
    require_eq "$(uname -r)" "$EXPECTED_KERNEL" 'unsupported source kernel'
    require_eq "$(sed -n 's/^shortname=//p' /proc/ubnthal/system.info | head -n1)" UNVR4 'target is not a four-bay UNVR'
    [[ -b /dev/boot && -b /dev/boot1 ]] || die 'expected internal boot medium is absent'
    require_eq "$(blockdev --getsize64 /dev/boot)" 31268536320 'internal boot-medium geometry mismatch'
    assert_mtd_layout
    validate_normalization_bootloader "$physical_version"
    [[ ! -e "$STATE_ROOT" && ! -e "$RUNTIME_ROOT" ]] || die 'existing conversion state must be rolled back before firmware normalization'
    [[ -z "$(pkg_version unifi-drive)" ]] || die 'Drive is already installed; firmware normalization requires a stock UNVR'
    [[ ! -e /var/run/fwupdate.pid ]] || die 'another firmware update is active'
    ! pgrep -x fwupdate >/dev/null 2>&1 || die 'another firmware update process is active'
    [[ ! -e /boot/firmware/rootfs.new ]] || die 'an incomplete firmware update is present'
    grep -q '^  schedule: null$' /data/unifi-core/config/firmware.yaml \
        || die 'console automatic updates are not disabled'
    grep -q '^  includeApplications: false$' /data/unifi-core/config/firmware.yaml \
        || die 'application automatic updates are not disabled'
    [[ -x /sbin/ubnt-systool && -x /sbin/ubnt-tools ]] || die 'stock Ubiquiti updater is unavailable'
    command -v fwinfo >/dev/null 2>&1 || die 'stock firmware metadata verifier is unavailable'
    storage_topology_token >/dev/null
    printf 'SOURCE_VERSION=%s\n' "$physical_version"
    printf 'SOURCE_DISK_STATE=preserved\n'
}

stage_normalization_image() {
    require_root
    local image_dir part core_cache core_size available_kib required_kib pid actual
    local expected_core_command curl_args
    normalization_source_preflight
    image_dir=$(dirname "$NORMALIZATION_IMAGE")
    part="$NORMALIZATION_IMAGE.part"
    core_cache=/data/unifi-core/firmware/fwupdate.bin
    expected_core_command="/usr/bin/curl -L -o $core_cache -C - --progress-bar $NORMALIZATION_IMAGE_URL"
    install -d -m 700 "$image_dir"
    if [[ -f "$NORMALIZATION_IMAGE" ]] &&
       [[ "$(stat -c %s "$NORMALIZATION_IMAGE")" == "$NORMALIZATION_IMAGE_SIZE" ]] &&
       [[ "$(sha "$NORMALIZATION_IMAGE")" == "$NORMALIZATION_IMAGE_SHA256" ]]; then
        validate_normalization_image
        return
    fi
    rm -f -- "$NORMALIZATION_IMAGE" "$part"
    trap 'rm -f -- "$part"' EXIT ERR HUP INT TERM
    available_kib=$(df -Pk "$image_dir" | awk 'NR == 2 {print $4}')
    required_kib=$((NORMALIZATION_IMAGE_SIZE / 1024 + 131072))
    [[ "$available_kib" =~ ^[0-9]+$ && "$available_kib" -ge "$required_kib" ]] \
        || die 'insufficient internal staging space for the signed normalization image'
    while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cmdline" ]] || continue
        actual=$(tr '\0' ' ' < "/proc/$pid/cmdline")
        actual=${actual% }
        [[ "$actual" == "$expected_core_command" ]] || continue
        kill -TERM "$pid"
        for _ in 1 2 3 4 5; do
            [[ ! -d "/proc/$pid" ]] && break
            sleep 1
        done
        [[ ! -d "/proc/$pid" ]] || die 'could not stop the orphaned stock firmware download safely'
    done < <(pgrep -x curl 2>/dev/null || true)
    if [[ -f "$core_cache" ]]; then
        core_size=$(stat -c %s "$core_cache")
        if [[ "$core_size" =~ ^[0-9]+$ && "$core_size" -gt 0 && "$core_size" -le "$NORMALIZATION_IMAGE_SIZE" ]]; then
            cp -- "$core_cache" "$part"
        fi
    fi
    if [[ ! -f "$part" || "$(stat -c %s "$part")" != "$NORMALIZATION_IMAGE_SIZE" ]]; then
        curl_args=(--fail --location --silent --show-error
            --proto '=https' --tlsv1.2 --connect-timeout 20
            --retry 5 --retry-delay 3 --retry-connrefused
            --speed-limit 131072 --speed-time 60)
        [[ ! -f "$part" ]] || curl_args+=(--continue-at -)
        if ! curl "${curl_args[@]}" --output "$part" "$NORMALIZATION_IMAGE_URL"; then
            rm -f -- "$part"
            die 'firmware download stalled; verify the UNVR network receive path'
        fi
    fi
    require_eq "$(stat -c %s "$part")" "$NORMALIZATION_IMAGE_SIZE" 'downloaded UNVR 5.1.33 image size mismatch'
    require_eq "$(sha "$part")" "$NORMALIZATION_IMAGE_SHA256" 'downloaded UNVR 5.1.33 image hash mismatch'
    /sbin/ubnt-tools fwupdate -dc "$part" >/dev/null 2>&1 \
        || die 'stock updater rejected the downloaded UNVR 5.1.33 image'
    case "$(fwinfo -k "$part" 2>/dev/null || true)" in
        UNVR4.al324.v5.1.33.*) ;;
        *) die 'downloaded normalization image metadata is not UNVR 5.1.33' ;;
    esac
    chmod 600 "$part"
    sync
    mv -f "$part" "$NORMALIZATION_IMAGE"
    sync
    trap - EXIT ERR HUP INT TERM
    log 'downloaded and verified the exact signed UNVR 5.1.33 normalization image'
}

validate_normalization_image() {
    normalization_source_preflight
    [[ -f "$NORMALIZATION_IMAGE" ]] || die 'exact signed UNVR 5.1.33 normalization image is missing'
    require_eq "$(stat -c %s "$NORMALIZATION_IMAGE")" "$NORMALIZATION_IMAGE_SIZE" 'UNVR 5.1.33 normalization image size mismatch'
    require_eq "$(sha "$NORMALIZATION_IMAGE")" "$NORMALIZATION_IMAGE_SHA256" 'UNVR 5.1.33 normalization image hash mismatch'
    /sbin/ubnt-tools fwupdate -dc "$NORMALIZATION_IMAGE" >/dev/null 2>&1 \
        || die 'stock updater rejected the signed UNVR 5.1.33 normalization image'
    case "$(fwinfo -k "$NORMALIZATION_IMAGE" 2>/dev/null || true)" in
        UNVR4.al324.v5.1.33.*) ;;
        *) die 'normalization image metadata is not UNVR 5.1.33' ;;
    esac
    log 'stock updater accepted the exact signed UNVR 5.1.33 normalization image'
}

normalize_to_5x() {
    validate_normalization_image
    sync
    log 'starting stock signed firmware normalization to UNVR 5.1.33'
    exec /sbin/ubnt-systool fwupdate "$NORMALIZATION_IMAGE"
}

preflight_5x() {
    if phase_done direct-5x-profile; then
        assert_base_5_runtime
        validate_direct_profile_resume_5x allow-inactive-services
    elif [[ -f "$STATE_ROOT/direct-profile-in-progress" ]] ||
         [[ "$(sha /usr/share/unifi-core/app/service.js 2>/dev/null || true)" == "$CORE_5_UNAS_HASH" ]]; then
        assert_base_5_runtime
        validate_direct_profile_in_progress_5x
    else
        assert_base_5_clean
        if [[ ! -e "$STATE_ROOT" && ! -e "$RUNTIME_ROOT" ]]; then
            :
        elif [[ -d "$STATE_ROOT" && -d "$RUNTIME_ROOT" ]]; then
            validate_clean_5x_resume_state
        else
            die 'incomplete or untracked installer/runtime state exists on the clean 5.1 baseline'
        fi
    fi
    grep -q '^isSetup: true$' /data/unifi-core/config/settings.yaml \
        || die 'complete normal UNVR setup and enable SSH before conversion'
    grep -q '^  schedule: null$' /data/unifi-core/config/firmware.yaml \
        || die 'turn off console automatic updates before conversion'
    grep -q '^  includeApplications: false$' /data/unifi-core/config/firmware.yaml \
        || die 'turn off application automatic updates before conversion'
    if [[ -f "$STATE_ROOT/clean-disk-state" && -f "$RUNTIME_ROOT/prestorage-block-usd" ]]; then
        validate_prestorage_usd_guard
    elif phase_done factory-pool-erased; then
        ! systemctl is-failed --quiet usd.service || die 'usd failed after the completed factory-pool erase'
    else
        systemctl is-active --quiet usd.service || die 'usd is not active'
    fi
    systemctl is-active --quiet uhwd.service || die 'uhwd is not active'
    [[ -s /etc/ustd/storage.conf ]] || die 'USTD storage configuration missing'
    log 'preflight passed: exact validated UNVR 5.1.33 conversion state'
}

validate_direct_profile_in_progress_5x() {
    phase_done backup || die 'partial direct profile is missing the rollback backup'
    phase_done update-guard || die 'partial direct profile is missing the update guard'
    phase_done dedicated-guard || die 'partial direct profile is missing the Protect guard'
    phase_done modules || die 'partial direct profile is missing native modules'
    validate_prestorage_disk_resume_state
    case "$(pkg_version unifi-drive)" in
        ''|4.3.10) ;;
        *) die 'partial direct profile has an unexpected Drive version' ;;
    esac
    case "$(sha /usr/share/unifi-core/app/service.js)" in
        "$CORE_5_STOCK_HASH") ;;
        "$CORE_5_UNAS_HASH"|"$PREVIOUS_CORE_5_UNAS_HASH")
            require_eq "$(cat "$RUNTIME_ROOT/logical-target" 2>/dev/null || true)" 5.1.33 \
                'partial direct profile logical target mismatch'
            case "$(sha /usr/lib/uid-agent/unifi-os-consoles.json)" in
                a7db66c52b418eb39bc2f66f5fc73f5a55083237863ffec50f921ecf303dbe35|\
                424c7f663a94a06557d379d47944734483ee039467ebbb3c5ea750b6f99e5f32) ;;
                *) die 'partial direct profile UID identity mismatch' ;;
            esac
            case "$(sha /usr/lib/ulp-go/unifi-os-console.json)" in
                4accb0af048a5a52deb9ff0c60a0fb98c72d9a4efd0fa7e48721117f94bdad1b|\
                29c94693d4586d20352c9aee22c08fa1f8c734a68fe588905d5b590babcd78f7) ;;
                *) die 'partial direct profile ULP identity mismatch' ;;
            esac
            ;;
        *) die 'partial direct profile Core state is unrecognized' ;;
    esac
    log 'validated resumable in-progress direct 5.1 UNAS profile'
}

validate_direct_profile_resume_5x() {
    local service_mode=${1:-require-active-services} installed_payload_version
    phase_done backup || die 'direct-profile resume is missing the rollback backup'
    phase_done update-guard || die 'direct-profile resume is missing the update guard'
    phase_done dedicated-guard || die 'direct-profile resume is missing the Protect guard'
    phase_done modules || die 'direct-profile resume is missing native modules'
    validate_prestorage_disk_resume_state
    if [[ -e "$RUNTIME_ROOT/installer-payload-version" ]]; then
        [[ -f "$RUNTIME_ROOT/installer-payload-version" && ! -L "$RUNTIME_ROOT/installer-payload-version" ]] \
            || die 'installer payload version marker is unsafe'
        installed_payload_version=$(cat "$RUNTIME_ROOT/installer-payload-version")
        if [[ "$installed_payload_version" != "$PAYLOAD_VERSION" ]]; then
            [[ "$service_mode" == allow-inactive-services && "$installed_payload_version" =~ ^(8|9|10|11|12|13|14|15|16|17|18|19|20|21)$ ]] \
                || die 'installer payload version mismatch'
        fi
        validate_identity_dependencies_5x
    fi
    case "$(pkg_version unifi-drive)" in
        ''|4.3.10) ;;
        *) die 'unexpected Drive version before the completed direct package phase' ;;
    esac
    if [[ "$service_mode" == allow-inactive-services &&
          "$(sha /usr/share/unifi-core/app/service.js)" == "$PREVIOUS_CORE_5_UNAS_HASH" ]]; then
        : # The profile phase refreshes this exact prior build before resuming.
    else
        require_eq "$(sha /usr/share/unifi-core/app/service.js)" "$CORE_5_UNAS_HASH" 'direct-profile Core identity hash mismatch'
    fi
    require_eq "$(sha /usr/lib/uid-agent/unifi-os-consoles.json)" 424c7f663a94a06557d379d47944734483ee039467ebbb3c5ea750b6f99e5f32 'direct-profile UID identity hash mismatch'
    require_eq "$(sha /usr/lib/ulp-go/unifi-os-console.json)" 29c94693d4586d20352c9aee22c08fa1f8c734a68fe588905d5b590babcd78f7 'direct-profile ULP identity hash mismatch'
    require_eq "$(sha /usr/share/unifi-core/app/node_modules/@ubnt/uhd-setup/dist/index.html)" cff883330a7bb3ab378053ddd9611f22efea8a4ff22863f9cfd59aeda0fa831c 'direct-profile generated setup manifest mismatch'
    require_eq "$(sha /usr/share/unifi-core/app/node_modules/@ubnt/unifi-portal/dist/local/index.html)" 8e81c708d68c18385139422d1ab34d95a2d5a4a538d47797db2c8d15a6542d1c 'direct-profile generated portal manifest mismatch'
    require_eq "$(cat "$RUNTIME_ROOT/logical-target" 2>/dev/null || true)" 5.1.33 'direct-profile logical target mismatch'
    [[ -f "$RUNTIME_ROOT/enabled" ]] || die 'direct-profile runtime enable marker is missing'
    require_eq "$(sha "$RUNTIME_ROOT/recovery/uImage-5.1.33")" 158688310a8fbef461c2f72a1d05326a246bcfa8525e3dc77177454853c462da 'direct-profile signed recovery kernel mismatch'
    local source_kernel_hash source_rootfs_hash source_rootfs_version unit
    source_kernel_hash=$(cat "$RUNTIME_ROOT/recovery/uImage-source.bkp.sha256" 2>/dev/null || true)
    [[ "$source_kernel_hash" =~ ^[0-9a-f]{64}$ ]] || die 'direct-profile source recovery hash is invalid'
    require_eq "$(sha "$RUNTIME_ROOT/recovery/uImage-source.bkp")" "$source_kernel_hash" 'direct-profile source recovery copy mismatch'
    source_rootfs_hash=$(cat "$RUNTIME_ROOT/recovery/rootfs-source.bkp.sha256" 2>/dev/null || true)
    source_rootfs_version=$(cat "$RUNTIME_ROOT/recovery/rootfs-source.bkp.version" 2>/dev/null || true)
    [[ "$source_rootfs_hash" =~ ^[0-9a-f]{64}$ ]] || die 'direct-profile source rootfs hash is invalid'
    [[ "$source_rootfs_version" == UNVR4.al324.v* ]] || die 'direct-profile source rootfs version is invalid'
    require_eq "$(sha /boot/firmware/rootfs.bkp)" "$source_rootfs_hash" 'direct-profile source rootfs changed'
    require_eq "$(head -c 4 /boot/firmware/rootfs.bkp | od -An -tx1 | tr -d ' \n')" 68737173 'direct-profile source rootfs is not SquashFS'
    validate_prestorage_disk_resume_state
    systemctl is-enabled --quiet unvr-unas-identity-restore.service || die 'identity restore unit is not enabled for direct-profile resume'
    if [[ "$service_mode" == require-active-services ]]; then
        for unit in uid-agent ulp-go unifi-core uhwd; do
            systemctl is-active --quiet "$unit" || die "$unit is not active after direct-profile reconciliation"
        done
    elif [[ "$service_mode" != allow-inactive-services ]]; then
        die 'invalid direct-profile service validation mode'
    fi
    verify_5x_backup
    log 'validated resumable direct 5.1 UNAS identity profile'
}

verify_5x_backup() {
    local backup
    [[ -f "$BACKUP_LINK" && ! -L "$BACKUP_LINK" ]] || die 'validated 5.1 backup link is missing'
    backup=$(cat "$BACKUP_LINK")
    [[ "$backup" =~ ^/data/unvr-unas-backup/[0-9]{8}T[0-9]{6}Z$ ]] \
        || die 'validated 5.1 backup path is malformed'
    [[ -d "$backup" && ! -L "$backup" && -f "$backup/SHA256SUMS" ]] \
        || die 'validated 5.1 backup directory is incomplete'
    (cd "$backup" && sha256sum -c SHA256SUMS >/dev/null) \
        || die 'validated 5.1 backup manifest failed'
}

validate_clean_5x_resume_state() {
    local entry marker file
    [[ -f "$STATE_ROOT/version" && "$(cat "$STATE_ROOT/version")" == "$INSTALLER_VERSION" ]] \
        || die 'installer resume state belongs to another version'
    [[ ! -e "$STATE_ROOT/ROLLED_BACK" ]] || die 'rolled-back installer state cannot be resumed'
    [[ -d "$STATE_ROOT/phases" && ! -L "$STATE_ROOT/phases" ]] || die 'installer phase directory is invalid'
    while IFS= read -r entry; do
        case "$entry" in
            version|backup-dir|clean-disk-state|kbuild-owned|phases|phases/backup.done|phases/update-guard.done|phases/dedicated-guard.done|phases/modules.done|phases/factory-pool-erased.done) ;;
            *) die "unexpected clean-baseline resume artifact: $entry" ;;
        esac
    done < <(find "$STATE_ROOT" -mindepth 1 -printf '%P\n' | LC_ALL=C sort)
    for marker in "$STATE_ROOT/phases/"*.done; do
        [[ -e "$marker" ]] || continue
        case "${marker##*/}" in
            backup.done|update-guard.done|dedicated-guard.done|modules.done|factory-pool-erased.done) ;;
            *) die "unsupported completed phase on clean-baseline resume: ${marker##*/}" ;;
        esac
    done
    [[ -f "$STATE_ROOT/clean-disk-state" ]] || die 'clean-baseline resume is missing its validated disk marker'
    if [[ -e "$STATE_ROOT/kbuild-owned" ]]; then
        [[ -f "$STATE_ROOT/kbuild-owned" && ! -L "$STATE_ROOT/kbuild-owned" ]] \
            || die 'kernel-build ownership marker is unsafe'
        require_eq "$(cat "$STATE_ROOT/kbuild-owned")" "$KBUILD_ROOT" \
            'kernel-build ownership marker is invalid'
        [[ ! -e "$KBUILD_ROOT" || ( -d "$KBUILD_ROOT" && ! -L "$KBUILD_ROOT" ) ]] \
            || die 'owned kernel-build chroot is unsafe'
    fi
    if phase_done backup; then
        verify_5x_backup
    else
        [[ -z "$(find "$STATE_ROOT/phases" -mindepth 1 -print -quit)" ]] \
            || die 'clean-baseline resume has phase markers before its rollback backup'
    fi
    while IFS= read -r file; do
        case "$file" in
            prestorage-block-usd|modules|"modules/$EXPECTED_KERNEL") ;;
            "modules/$EXPECTED_KERNEL/zstd_compress.ko")
                if phase_done modules || [[ ! -f "$STATE_ROOT/kbuild-owned" ]]; then
                    require_eq "$(sha "$RUNTIME_ROOT/$file")" "$ZSTD_MODULE_HASH" 'resumed zstd module hash mismatch'
                fi
                ;;
            "modules/$EXPECTED_KERNEL/btrfs.ko")
                if phase_done modules || [[ ! -f "$STATE_ROOT/kbuild-owned" ]]; then
                    require_eq "$(sha "$RUNTIME_ROOT/$file")" "$BTRFS_MODULE_HASH" 'resumed Btrfs module hash mismatch'
                fi
                ;;
            "modules/$EXPECTED_KERNEL/fuse.ko")
                if phase_done modules || [[ ! -f "$STATE_ROOT/kbuild-owned" ]]; then
                    require_eq "$(sha "$RUNTIME_ROOT/$file")" "$FUSE_MODULE_HASH" 'resumed FUSE module hash mismatch'
                fi
                ;;
            *) die "unexpected clean-baseline runtime artifact: $file" ;;
        esac
    done < <(find "$RUNTIME_ROOT" -mindepth 1 -printf '%P\n' | LC_ALL=C sort)
    log 'validated resumable clean 5.1 installer state'
}

init_state() {
    [[ ! -f "$STATE_ROOT/ROLLED_BACK" ]] || die 'this installer state was rolled back and cannot be resumed automatically'
    [[ ! -e "$STATE_ROOT" || ( -d "$STATE_ROOT" && ! -L "$STATE_ROOT" ) ]] \
        || die 'installer state path is not a safe directory'
    [[ ! -e "$RUNTIME_ROOT" || ( -d "$RUNTIME_ROOT" && ! -L "$RUNTIME_ROOT" ) ]] \
        || die 'runtime state path is not a safe directory'
    install -d -m 700 "$STATE_ROOT" "$STATE_ROOT/phases"
    install -d -m 755 "$RUNTIME_ROOT"
    if [[ -f "$STATE_ROOT/version" ]]; then
        [[ ! -L "$STATE_ROOT/version" ]] || die 'installer version marker is a symlink'
        require_eq "$(cat "$STATE_ROOT/version")" "$INSTALLER_VERSION" 'installer state belongs to another version'
    else
        local version_tmp
        version_tmp=$(mktemp "$STATE_ROOT/.version.XXXXXX")
        trap 'rm -f -- "$version_tmp"' RETURN EXIT HUP INT TERM
        printf '%s\n' "$INSTALLER_VERSION" > "$version_tmp"
        chmod 600 "$version_tmp"
        sync "$version_tmp"
        mv -f "$version_tmp" "$STATE_ROOT/version"
        sync "$STATE_ROOT/version"
        trap - RETURN EXIT HUP INT TERM
    fi
}

cleanup_normalization_staging() {
    local part="$NORMALIZATION_IMAGE.part"
    [[ ! -e "$part" ]] || die 'incomplete normalization image staging remains'
    if [[ -e "$NORMALIZATION_IMAGE" ]]; then
        [[ -f "$NORMALIZATION_IMAGE" && ! -L "$NORMALIZATION_IMAGE" ]] \
            || die 'normalization image path is unsafe'
        require_eq "$(stat -c %s "$NORMALIZATION_IMAGE")" "$NORMALIZATION_IMAGE_SIZE" 'staged normalization image size changed'
        require_eq "$(sha "$NORMALIZATION_IMAGE")" "$NORMALIZATION_IMAGE_SHA256" 'staged normalization image hash changed'
        rm -f -- "$NORMALIZATION_IMAGE"
        sync
    fi
}

backup_phase() {
    assert_base
    if [[ ! -f "$STATE_ROOT/version" ]]; then
        require_eq "$(sha /usr/share/unifi-core/app/service.js)" "$CORE_ORIGINAL_HASH" 'new installation requires the exact unpatched Core bundle'
        ! dpkg-query -W unifi-drive >/dev/null 2>&1 || die 'new installation requires Drive to be absent'
        [[ ! -e "$RUNTIME_ROOT" ]] || die 'untracked UNVR-UNAS runtime state already exists'
    fi
    init_state
    phase_done backup && { log 'backup phase already complete'; return; }
    [[ ! -e "$BACKUP_LINK" ]] || die 'unexpected incomplete backup state'
    local backup stamp
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    backup="/data/unvr-unas-backup/$stamp"
    [[ ! -e "$backup" ]] || die 'backup timestamp collision'
    install -d -m 700 "$backup/config" "$backup/databases"
    cp -a /usr/share/unifi-core/app/service.js "$backup/config/core-service.js"
    cp -a /etc/ustd/storage.conf "$backup/config/storage.conf"
    cp -a /etc/hostname "$backup/config/hostname"
    cp -a /etc/hosts "$backup/config/hosts"
    cp -a /usr/lib/uid-agent/unifi-os-consoles.json "$backup/config/uid-unifi-os-consoles.json"
    cp -a /usr/lib/ulp-go/unifi-os-console.json "$backup/config/ulp-unifi-os-console.json"
    cp -a /usr/share/unifi-core/app/node_modules/@ubnt/unifi-portal/dist/local/index.html "$backup/config/portal-index.html"
    tar -C /usr/share/unifi-assets -czf "$backup/config/unifi-assets.tar.gz" .
    [[ ! -e /etc/samba/smb.conf ]] || cp -a /etc/samba/smb.conf "$backup/config/smb.conf"
    [[ ! -e /etc/exports ]] || cp -a /etc/exports "$backup/config/exports"
    dpkg-query -W -f='${binary:Package}\t${Version}\n' | sort > "$backup/packages.tsv"
    apt-mark showhold | sort > "$backup/apt-holds.txt"
    systemctl list-unit-files --no-legend > "$backup/unit-files.txt"
    for unit in unifi-protect.service postgresql@14-protect.service postgresql-cluster@14-protect.service postgresql-cluster-14-protect-cleanup.service ms.service msp.service msr.service mst.service ds.service ds-monitor.service msx-monitor.service ai-feature-console.service apt-daily.timer apt-daily-upgrade.timer; do
        printf '%s\t%s\t%s\n' "$unit" "$(systemctl is-active "$unit" 2>/dev/null || true)" "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    done > "$backup/service-state.tsv"
    if sudo -u postgres psql -X -lqt 2>/dev/null | awk -F '|' '{gsub(/ /,"",$1); print $1}' | grep -qx unifi-drive; then
        dump_postgres_database unifi-drive "$backup/databases/unifi-drive.dump"
    fi
    (
        cd "$backup"
        find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
        sha256sum -c SHA256SUMS >/dev/null
    )
    printf '%s\n' "$backup" > "$BACKUP_LINK"
    sync "$BACKUP_LINK"
    mark_done backup
    log 'software/configuration backup verified on /data'
}

backup_5x_phase() {
    if phase_done backup; then
        assert_base_5_runtime
        verify_5x_backup
        cleanup_normalization_staging
        log 'clean 5.1 software/configuration backup already complete and verified'
        return
    fi
    assert_base_5_clean
    if [[ -e "$STATE_ROOT" || -e "$RUNTIME_ROOT" ]]; then
        [[ -d "$STATE_ROOT" && -d "$RUNTIME_ROOT" ]] || die 'incomplete state before clean 5.1 backup resume'
        validate_clean_5x_resume_state
    fi
    init_state
    local backup stamp database
    require_free_bytes /data 1073741824 'the rollback backup'
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    backup="/data/unvr-unas-backup/$stamp"
    [[ ! -e "$backup" ]] || die 'backup timestamp collision'
    install -d -m 700 "$backup/config" "$backup/databases"
    cp -a /usr/share/unifi-core/app/service.js "$backup/config/core-service.js"
    cp -a /etc/ustd/storage.conf "$backup/config/storage.conf"
    cp -a /etc/hostname "$backup/config/hostname"
    cp -a /etc/hosts "$backup/config/hosts"
    cp -a /usr/lib/uid-agent/unifi-os-consoles.json "$backup/config/uid-unifi-os-consoles.json"
    cp -a /usr/lib/ulp-go/unifi-os-console.json "$backup/config/ulp-unifi-os-console.json"
    cp -a /data/unifi-core/config/firmware.yaml "$backup/config/firmware.yaml"
    cp -a /data/unifi-core/config/settings.yaml "$backup/config/settings.yaml"
    cp -a /usr/share/unifi-core/app/node_modules/@ubnt/uhd-setup/dist/index.html "$backup/config/uhd-setup-index.html"
    cp -a /usr/share/unifi-core/app/node_modules/@ubnt/unifi-portal/dist/local/index.html "$backup/config/portal-index.html"
    tar -C /usr/share/unifi-assets -czf "$backup/config/unifi-assets.tar.gz" .
    [[ ! -e /etc/samba/smb.conf ]] || cp -a /etc/samba/smb.conf "$backup/config/smb.conf"
    [[ ! -e /etc/exports ]] || cp -a /etc/exports "$backup/config/exports"
    dpkg-query -W -f='${binary:Package}\t${Version}\n' | sort > "$backup/packages.tsv"
    apt-mark showhold | sort > "$backup/apt-holds.txt"
    systemctl list-unit-files --no-legend > "$backup/unit-files.txt"
    for unit in unifi-protect.service postgresql@14-protect.service postgresql-cluster@14-protect.service postgresql-cluster-14-protect-cleanup.service ms.service msp.service msr.service mst.service ds.service ds-monitor.service msx-monitor.service ai-feature-console.service apt-daily.timer apt-daily-upgrade.timer; do
        printf '%s\t%s\t%s\n' "$unit" "$(systemctl is-active "$unit" 2>/dev/null || true)" "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    done > "$backup/service-state.tsv"
    for database in ulp-go unifi-core; do
        if sudo -u postgres psql -X -lqt 2>/dev/null | awk -F '|' '{gsub(/ /,"",$1); print $1}' | grep -qx "$database"; then
            dump_postgres_database "$database" "$backup/databases/$database.dump"
        fi
    done
    (
        cd "$backup"
        find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
        sha256sum -c SHA256SUMS >/dev/null
    )
    printf '%s\n' "$backup" > "$BACKUP_LINK"
    sync "$BACKUP_LINK"
    mark_done backup
    cleanup_normalization_staging
    log 'clean 5.1 software/configuration backup verified on /data'
}

validate_stock_unas_apt_policy() {
    local target=/etc/apt/apt.conf.d/10validuntil
    [[ -f "$target" && ! -L "$target" ]] || die 'stock UNAS APT validity policy is missing or unsafe'
    require_eq "$(stat -c '%U:%G:%a' "$target")" root:root:644 'stock UNAS APT validity policy metadata is invalid'
    require_eq "$(sha "$target")" "$STOCK_UNAS_VALID_UNTIL_SHA256" 'stock UNAS APT validity policy is invalid'
}

ensure_stock_unas_apt_policy() {
    local target=/etc/apt/apt.conf.d/10validuntil tmp
    if [[ -e "$target" || -L "$target" ]]; then
        validate_stock_unas_apt_policy
        return
    fi
    [[ -d /etc/apt/apt.conf.d && ! -L /etc/apt/apt.conf.d ]] \
        || die 'APT configuration directory is missing or unsafe'
    tmp=$(mktemp /etc/apt/apt.conf.d/.10validuntil.XXXXXX)
    trap 'rm -f -- "$tmp"' RETURN EXIT HUP INT TERM
    printf 'Acquire::Check-Valid-Until "false";\n' > "$tmp"
    chown root:root "$tmp"
    chmod 0644 "$tmp"
    require_eq "$(sha "$tmp")" "$STOCK_UNAS_VALID_UNTIL_SHA256" 'generated stock UNAS APT validity policy is invalid'
    sync "$tmp"
    mv -f "$tmp" "$target"
    sync "$target"
    trap - RETURN EXIT HUP INT TERM
    validate_stock_unas_apt_policy
}

auto_update_guard_phase() {
    assert_supported_base
    init_state
    ensure_stock_unas_apt_policy
    if phase_done update-guard; then
        [[ -f /etc/apt/apt.conf.d/99-unvr-unas-no-periodic && ! -L /etc/apt/apt.conf.d/99-unvr-unas-no-periodic ]] \
            || die 'periodic APT guard is missing or unsafe'
        require_eq "$(sha /etc/apt/apt.conf.d/99-unvr-unas-no-periodic)" \
            7bcabe17b75c267977064e1fddccdcb09257b06c227ab13b7f7d22d4f74007fd \
            'periodic APT guard is invalid'
        local held
        held=$(apt-mark showhold)
        for package in unifi-core ustd ustate-exporter ubntnas unifi-hal ubnt-tools unifi-protect; do
            grep -qx "$package" <<<"$held" || die "platform package hold is missing: $package"
        done
        for unit in apt-daily.timer apt-daily-upgrade.timer; do
            require_eq "$(systemctl is-enabled "$unit" 2>/dev/null || true)" masked "periodic APT timer is not masked: $unit"
            ! systemctl is-active --quiet "$unit" || die "periodic APT timer is active: $unit"
        done
        log 'update guard and stock UNAS APT policy already complete and verified'
        return
    fi
    local unit
    for unit in apt-daily.timer apt-daily-upgrade.timer; do
        systemctl disable --now "$unit" >/dev/null 2>&1 || true
        systemctl mask "$unit" >/dev/null
    done
    cat > /etc/apt/apt.conf.d/99-unvr-unas-no-periodic <<'EOF'
APT::Periodic::Enable "0";
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::Unattended-Upgrade "0";
EOF
    apt-mark hold unifi-core ustd ustate-exporter ubntnas unifi-hal ubnt-tools unifi-protect >/dev/null
    mark_done update-guard
    log 'stock UNAS APT policy installed, periodic activity disabled and validated platform packages held'
}

core_patch_phase() {
    assert_base
    init_state
    phase_done core-patch && { log 'Core patch already complete'; return; }
    [[ -f "$STATE_ROOT/build_core_dashboard_patch.js" ]] || die 'Core patch builder was not staged'
    require_eq "$(sha "$STATE_ROOT/build_core_dashboard_patch.js")" 7a75337c389678449af03f796d0880fa5b66bd008e6971fa7881525f8573ee1f 'Core patch builder hash mismatch'
    local current backup
    current=$(sha /usr/share/unifi-core/app/service.js)
    backup=$(cat "$BACKUP_LINK")
    if [[ "$current" == "$CORE_ORIGINAL_HASH" ]]; then
        require_eq "$(sha "$backup/config/core-service.js")" "$CORE_ORIGINAL_HASH" 'Core backup hash mismatch'
        /usr/bin/node18 "$STATE_ROOT/build_core_dashboard_patch.js" /usr/share/unifi-core/app/service.js "$STATE_ROOT/service.js.patched" >/dev/null
        require_eq "$(sha "$STATE_ROOT/service.js.patched")" "$CORE_PATCHED_HASH" 'generated Core patch hash mismatch'
        install -o root -g root -m 644 "$STATE_ROOT/service.js.patched" /usr/share/unifi-core/app/service.js.new
        sync
        mv -f /usr/share/unifi-core/app/service.js.new /usr/share/unifi-core/app/service.js
        sync
        systemctl restart unifi-core.service
    elif [[ "$current" != "$CORE_PATCHED_HASH" ]]; then
        die 'unexpected Core bundle state'
    fi
    require_eq "$(sha /usr/share/unifi-core/app/service.js)" "$CORE_PATCHED_HASH" 'installed Core patch hash mismatch'
    mark_done core-patch
    log 'Drive catalog enabled without changing product identity'
}

find_downloaded_deb() {
    local package=$1 version=$2 file p v
    while IFS= read -r file; do
        p=$(dpkg-deb -f "$file" Package 2>/dev/null || true)
        v=$(dpkg-deb -f "$file" Version 2>/dev/null || true)
        if [[ "$p" == "$package" && "$v" == "$version" ]]; then printf '%s\n' "$file"; return 0; fi
    done < <(find /var/cache/apt/archives -maxdepth 1 -type f -name '*.deb' -print)
    return 1
}

verify_deb_against_signed_index() {
    local package=$1 version=$2 deb metadata_hash
    deb=$(find_downloaded_deb "$package" "$version") || die "downloaded $package package not found"
    metadata_hash=$(apt-cache show "$package=$version" | awk '/^SHA256: /{print $2; exit}')
    [[ "$metadata_hash" =~ ^[0-9a-f]{64}$ ]] || die "signed APT SHA-256 missing for $package"
    require_eq "$(sha "$deb")" "$metadata_hash" "downloaded $package SHA-256 mismatch"
    printf '%s\t%s\t%s\n' "$package" "$version" "$metadata_hash" >> "$STATE_ROOT/downloaded-packages.tsv"
}

packages_phase() {
    assert_base
    init_state
    if phase_done packages; then
        rm -f -- "$STATE_ROOT/wsdd.deb"
        require_eq "$(pkg_version unifi-drive)" 1.19.1 'installed Drive version drifted'
        require_eq "$(pkg_version unifi-drive-config)" 2.9.19-10+g496db739ef20 'installed Drive Config version drifted'
        require_eq "$(pkg_version unifi-drive-rclone)" 1.67.0-1+g2b3bd0b0f35e 'installed Drive rclone version drifted'
        require_eq "$(sha /usr/share/unifi-drive/bin/unifi-drive)" "$DRIVE_ORIGINAL_HASH" 'official Drive executable drifted'
        log 'package phase already complete and verified'
        return
    fi
    [[ -f "$STATE_ROOT/wsdd.deb" ]] || die 'official wsdd reconstruction was not staged'
    require_eq "$(dpkg-deb -f "$STATE_ROOT/wsdd.deb" Package)" wsdd 'staged package is not wsdd'
    require_eq "$(dpkg-deb -f "$STATE_ROOT/wsdd.deb" Version)" "$WSDD_VERSION" 'wsdd version mismatch'
    local verify_root
    verify_root=$(mktemp -d /run/unvr-wsdd-verify.XXXXXX)
    trap 'rm -rf -- "$verify_root"' RETURN
    dpkg-deb -x "$STATE_ROOT/wsdd.deb" "$verify_root"
    require_eq "$(sha "$verify_root/usr/sbin/wsdd")" "$WSDD_EXEC_HASH" 'wsdd principal executable hash mismatch'
    rm -rf -- "$verify_root"
    trap - RETURN
    DEBIAN_FRONTEND=noninteractive dpkg -i "$STATE_ROOT/wsdd.deb"

    apt-get update
    local specs=(
        'unifi-drive=1.19.1'
        'unifi-drive-config=2.9.19-10+g496db739ef20'
        'unifi-drive-rclone=1.67.0-1+g2b3bd0b0f35e'
        'btrfs-progs=5.10.1-2'
        'samba=2:4.13.13+dfsg-1~deb11u6'
        'samba-common=2:4.13.13+dfsg-1~deb11u6'
        'samba-common-bin=2:4.13.13+dfsg-1~deb11u6'
        'samba-libs=2:4.13.13+dfsg-1~deb11u6'
        'samba-vfs-modules=2:4.13.13+dfsg-1~deb11u6'
        'nfs-kernel-server=1:1.3.4-6+deb11u1'
    )
    local spec package version deb
    for spec in "${specs[@]}"; do
        package=${spec%%=*}; version=${spec#*=}
        require_eq "$(apt-cache policy "$package" | awk '/Candidate:/{print $2}')" "$version" "APT candidate mismatch for $package"
    done
    : > "$STATE_ROOT/downloaded-packages.tsv"
    DEBIAN_FRONTEND=noninteractive apt-get --download-only install -y "${specs[@]}"
    for spec in "${specs[@]}"; do
        package=${spec%%=*}; version=${spec#*=}
        verify_deb_against_signed_index "$package" "$version"
    done

    if [[ -e /etc/samba/smb.conf && ! -e /etc/samba/smb.conf.unvr-base ]]; then
        dpkg-divert --package unifi-drive-config --rename --add --divert /etc/samba/smb.conf.unvr-base /etc/samba/smb.conf
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${specs[@]}"
    require_eq "$(pkg_version unifi-drive)" 1.19.1 'Drive package version mismatch after install'
    require_eq "$(pkg_version unifi-drive-config)" 2.9.19-10+g496db739ef20 'Drive Config version mismatch after install'
    require_eq "$(pkg_version unifi-drive-rclone)" 1.67.0-1+g2b3bd0b0f35e 'Drive rclone version mismatch after install'
    require_eq "$(sha /usr/share/unifi-drive/bin/unifi-drive)" "$DRIVE_ORIGINAL_HASH" 'Drive 1.19.1 executable hash mismatch'
    local db_deadline=$((SECONDS + 120))
    while (( SECONDS < db_deadline )); do
        if sudo -u postgres psql -X -d unifi-drive -A -t -c "SELECT to_regclass('public.storages')" 2>/dev/null | grep -qx storages; then break; fi
        sleep 2
    done
    sudo -u postgres psql -X -d unifi-drive -A -t -c "SELECT to_regclass('public.storages')" | grep -qx storages || die 'Drive database migrations did not complete'
    systemctl stop unifi-drive.service
    # Do not apt-mark hold application packages: Core 4.1.140 only recognizes
    # dpkg `${Status}` strings beginning with `install`; a hold makes the
    # healthy application appear uninstalled in Core/ULP and hides it from the
    # dashboard. Periodic/automatic updates are disabled by update-guard.
    apt-mark unhold unifi-drive unifi-drive-config unifi-drive-rclone >/dev/null 2>&1 || true
    for spec in "${specs[@]}"; do
        package=${spec%%=*}; version=${spec#*=}
        deb=$(find_downloaded_deb "$package" "$version" || true)
        [[ -z "$deb" ]] || rm -f -- "$deb"
    done
    rm -f -- "$STATE_ROOT/wsdd.deb"
    mark_done packages
    log 'official Drive 1.19.1 stack installed and hash-verified'
}

verify_kbuild_mirror() {
    local mirror=$1 manifest=$2 filename package version architecture size expected_hash _content_hash
    [[ -d "$mirror" && ! -L "$mirror" && -f "$manifest" && ! -L "$manifest" ]] \
        || die 'kernel-build mirror or manifest is missing or unsafe'
    require_eq "$(sha "$manifest")" "$DEBIAN_KBUILD_CLOSURE_SHA256" 'kernel-build dependency manifest mismatch'
    require_eq "$(sha "$mirror/dists/bullseye/InRelease")" \
        7a888c9463d8c14a5fb7e8520b8ca942d0c08e5c446aa0066693131cc0e6761a 'kernel-build signed Release mismatch'
    require_eq "$(sha "$mirror/dists/bullseye/main/binary-arm64/Packages")" \
        29a803e05ffdf9fbabe7e35d7f26eae4433f1d05301d3ef160a9ee297944a8a5 'kernel-build package index mismatch'
    while IFS=$'\t' read -r filename package version architecture size expected_hash _content_hash; do
        verify_immutable_dependency_5x "$mirror/$filename" "$package" "$version" "$architecture" "$size" "$expected_hash"
    done < "$manifest"
}

validate_kbuild_packages() {
    local root=$1 manifest=$2 filename package version architecture size expected_hash _content_hash
    require_eq "$(sha "$manifest")" "$DEBIAN_KBUILD_CLOSURE_SHA256" 'kernel-build dependency manifest mismatch'
    while IFS=$'\t' read -r filename package version architecture size expected_hash _content_hash; do
        require_eq "$(chroot "$root" dpkg-query -W -f='${Version}|${Architecture}|${Status}' "$package")" \
            "$version|$architecture|install ok installed" "kernel-build package is incomplete or changed: $package"
    done < "$manifest"
    [[ -z "$(chroot "$root" dpkg --audit)" ]] || die 'kernel-build bootstrap has an incomplete package transaction'
}

build_modules_phase() {
    assert_supported_base
    init_state
    local module_dir="$RUNTIME_ROOT/modules/$EXPECTED_KERNEL" physical expected_bundle=${1:-}
    physical=$(cat /usr/lib/version)
    if phase_done modules; then
        require_eq "$(sha "$module_dir/zstd_compress.ko")" "$ZSTD_MODULE_HASH" 'persisted zstd module drifted'
        require_eq "$(sha "$module_dir/btrfs.ko")" "$BTRFS_MODULE_HASH" 'persisted Btrfs module drifted'
        require_eq "$(sha "$module_dir/fuse.ko")" "$FUSE_MODULE_HASH" 'persisted FUSE module drifted'
        log 'native module phase already complete and verified'
        return
    fi
    install -d -m 755 "$module_dir"
    if [[ ! -f "$module_dir/zstd_compress.ko" || ! -f "$module_dir/btrfs.ko" || ! -f "$module_dir/fuse.ko" ]] ||
       [[ "$(sha "$module_dir/zstd_compress.ko" 2>/dev/null || true)" != "$ZSTD_MODULE_HASH" ]] ||
       [[ "$(sha "$module_dir/btrfs.ko" 2>/dev/null || true)" != "$BTRFS_MODULE_HASH" ]] ||
        [[ "$(sha "$module_dir/fuse.ko" 2>/dev/null || true)" != "$FUSE_MODULE_HASH" ]]; then
        if [[ "$physical" == "$EXPECTED_OS_5" ]]; then
            local profile_bundle="$STATE_ROOT/update-profiles.tar.gz"
            local debootstrap_deb=/run/unvr-unas-debootstrap.deb
            [[ "$expected_bundle" =~ ^[0-9a-f]{64}$ ]] || die 'profile bundle SHA-256 is required for immutable module build setup'
            [[ -f "$profile_bundle" && ! -L "$profile_bundle" ]] || die 'profile bundle is unavailable for immutable module build setup'
            require_eq "$(sha "$profile_bundle")" "$expected_bundle" 'profile bundle hash mismatch before module build'
            tar -xOzf "$profile_bundle" ./packages/debootstrap_1.0.123+deb11u3_all.deb > "$debootstrap_deb"
            verify_immutable_dependency_5x "$debootstrap_deb" debootstrap 1.0.123+deb11u3 all 77788 \
                e14600a6b6770ee666419e114a1531bb8083b95c55ee26f0050cebaaba2c9943
            if [[ "$(pkg_version debootstrap)" != 1.0.123+deb11u3 ]] || ! pkg_configured debootstrap; then
                DEBIAN_FRONTEND=noninteractive dpkg -i "$debootstrap_deb" < /dev/null
            fi
            rm -f -- "$debootstrap_deb"
            require_eq "$(pkg_version debootstrap)" 1.0.123+deb11u3 'immutable debootstrap version mismatch'
            pkg_configured debootstrap || die 'immutable debootstrap package is not fully configured'
        elif ! dpkg-query -W debootstrap >/dev/null 2>&1; then
            die 'legacy 4.x module builds require a preinstalled debootstrap package'
        fi
        require_free_bytes /var/log 3221225472 'the reproducible native-module build workspace'
        local root=$KBUILD_ROOT src archive archive_part mirror_stage= mirror_manifest= member
        local build_includes=build-essential,bc,bison,flex,libssl-dev,libelf-dev,kmod,xz-utils,curl,ca-certificates
        archive="$root/usr/src/linux-4.19.152.tar.xz"
        archive_part="$root/usr/src/linux-4.19.152.tar.xz.part"
        if [[ -e "$root" ]]; then
            require_eq "$(cat "$STATE_ROOT/kbuild-owned" 2>/dev/null || true)" "$root" \
                'existing kernel-build chroot is not owned by this installer run'
        fi
        if [[ "$physical" == "$EXPECTED_OS_5" ]]; then
            mirror_stage=$(mktemp -d /var/log/unvr-kbuild-mirror.XXXXXX)
            trap '[[ -z "${mirror_stage:-}" ]] || rm -rf -- "$mirror_stage"' EXIT
            # Reject unsafe archive members before extracting the signed mirror.
            while IFS= read -r member; do
                [[ "$member" != /* && "$member" != ../* && "$member" != */../* ]] \
                    || die 'unsafe kernel-build payload path'
            done < <(tar -tzf "$profile_bundle")
            tar -xzf "$profile_bundle" -C "$mirror_stage" --no-same-owner \
                ./kbuild-mirror ./debian-kbuild-closure.tsv
            mirror_manifest="$mirror_stage/debian-kbuild-closure.tsv"
            verify_kbuild_mirror "$mirror_stage/kbuild-mirror" "$mirror_manifest"
        fi
        if [[ ! -x "$root/usr/bin/gcc" || ! -f "$root/.unvr-unas-bootstrap-complete" ]] ||
           [[ "$physical" == "$EXPECTED_OS_5" &&
              "$(cat "$root/.unvr-unas-bootstrap-complete" 2>/dev/null || true)" != "$DEBIAN_KBUILD_CLOSURE_SHA256" ]]; then
            if [[ -e "$root" ]]; then
                [[ -z "$(findmnt -rn -o TARGET | awk -v root="$root" '$0 == root || index($0, root "/") == 1')" ]] \
                    || die 'kernel-build chroot still has mounted filesystems; refusing cleanup'
                rm -rf -- "$root"
            fi
            printf '%s\n' "$root" > "$STATE_ROOT/kbuild-owned"
            local build_mirror=https://deb.debian.org/debian
            local -a bootstrap_prefix=()
            if [[ "$physical" == "$EXPECTED_OS_5" ]]; then
                build_mirror="file://$mirror_stage/kbuild-mirror"
                bootstrap_prefix=(unshare --net --)
            fi
            if ! "${bootstrap_prefix[@]}" debootstrap --force-check-gpg --variant=minbase --arch=arm64 --include="$build_includes" \
                bullseye "$root" "$build_mirror"; then
                die 'kernel-build bootstrap failed; see /var/log/unvr-kbuild-root/debootstrap/debootstrap.log'
            fi
            if [[ "$physical" == "$EXPECTED_OS_5" ]]; then
                validate_kbuild_packages "$root" "$mirror_manifest"
                printf '%s\n' "$DEBIAN_KBUILD_CLOSURE_SHA256" > "$root/.unvr-unas-bootstrap-complete"
            else
                printf '%s\n' legacy > "$root/.unvr-unas-bootstrap-complete"
            fi
            rm -rf -- "$root/var/cache/apt/archives" "$root/var/lib/apt/lists"
            install -d -m 0755 "$root/var/cache/apt/archives/partial" "$root/var/lib/apt/lists/partial"
        elif [[ "$physical" == "$EXPECTED_OS_5" ]]; then
            validate_kbuild_packages "$root" "$mirror_manifest"
        fi
        if [[ -n "$mirror_stage" ]]; then
            rm -rf -- "$mirror_stage"
            trap - EXIT
        fi
        require_eq "$(chroot "$root" dpkg-query -W -f='${Version}' gcc-10)" 10.2.1-6 'kernel-build compiler package mismatch'
        src="$root/usr/src/linux-4.19.152"
        if [[ -d "$src" ]] &&
           [[ ! -f "$src/Makefile" || ! -f "$src/fs/btrfs/Makefile" || ! -f "$src/fs/fuse/Makefile" || ! -f "$src/lib/zstd/Makefile" ]]; then
            rm -rf -- "$src"
        fi
        if [[ ! -d "$src" ]]; then
            if [[ ! -f "$archive" || "$(sha "$archive" 2>/dev/null || true)" != "$KERNEL_TARBALL_HASH" ]]; then
                rm -f -- "$archive" "$archive_part"
                curl -fL --proto '=https' --tlsv1.2 --connect-timeout 20 \
                    --retry 5 --retry-delay 3 --retry-connrefused \
                    --speed-limit 32768 --speed-time 120 \
                    "$KERNEL_TARBALL_URL" -o "$archive_part"
                require_eq "$(sha "$archive_part")" "$KERNEL_TARBALL_HASH" 'kernel.org source archive hash mismatch'
                mv -f "$archive_part" "$archive"
            fi
            tar -xJf "$archive" -C "$root/usr/src"
            [[ -f "$src/Makefile" && -f "$src/fs/btrfs/Makefile" && -f "$src/fs/fuse/Makefile" && -f "$src/lib/zstd/Makefile" ]] \
                || die 'kernel source extraction is incomplete'
        fi
        zcat /proc/config.gz > "$src/.config"
        if [[ "$physical" == "$EXPECTED_OS_5" ]]; then
            sed -i 's/^CONFIG_LOCALVERSION=""$/CONFIG_LOCALVERSION="-alpine-unvr"/' "$src/.config"
            grep -qx 'CONFIG_LOCALVERSION="-alpine-unvr"' "$src/.config" \
                || die 'could not apply the UNVR vendor kernel suffix'
        fi
        sed -i \
            -e 's/^# CONFIG_BTRFS_FS is not set$/CONFIG_BTRFS_FS=m/' \
            -e 's/^# CONFIG_FUSE_FS is not set$/CONFIG_FUSE_FS=m/' \
            "$src/.config"
        grep -qx 'CONFIG_BTRFS_FS=m' "$src/.config" || die 'could not enable Btrfs in exact UNVR config'
        grep -qx 'CONFIG_FUSE_FS=m' "$src/.config" || die 'could not enable FUSE in exact UNVR config'
        chroot "$root" /bin/bash -ceu '
            cd /usr/src/linux-4.19.152
            make olddefconfig
            grep -qx "CONFIG_ZSTD_COMPRESS=m" .config
            test "$(make -s kernelrelease)" = 4.19.152-alpine-unvr
            make -j2 prepare modules_prepare
            make -j2 M=lib/zstd modules
            make -j2 M=fs/btrfs modules
            make -j2 M=fs/fuse modules
        '
        require_eq "$(sha "$src/lib/zstd/zstd_compress.ko")" "$ZSTD_MODULE_HASH" 'native zstd_compress module is not byte-identical to validated build'
        require_eq "$(sha "$src/fs/btrfs/btrfs.ko")" "$BTRFS_MODULE_HASH" 'native Btrfs module is not byte-identical to validated build'
        require_eq "$(sha "$src/fs/fuse/fuse.ko")" "$FUSE_MODULE_HASH" 'native FUSE module is not byte-identical to validated build'
        install -o root -g root -m 644 "$src/lib/zstd/zstd_compress.ko" "$module_dir/zstd_compress.ko"
        install -o root -g root -m 644 "$src/fs/btrfs/btrfs.ko" "$module_dir/btrfs.ko"
        install -o root -g root -m 644 "$src/fs/fuse/fuse.ko" "$module_dir/fuse.ko"
        rm -rf -- "$root"
        rm -f -- "$STATE_ROOT/kbuild-owned"
    fi
    require_eq "$(modinfo -F vermagic "$module_dir/btrfs.ko")" "$EXPECTED_KERNEL SMP mod_unload aarch64" 'Btrfs module vermagic mismatch'
    require_eq "$(modinfo -F vermagic "$module_dir/fuse.ko")" "$EXPECTED_KERNEL SMP mod_unload aarch64" 'FUSE module vermagic mismatch'
    mark_done modules
    log 'exact native UNVR Btrfs modules built and verified'
}

write_sitecustomize() {
    cat > "$RUNTIME_ROOT/sitecustomize.py" <<'PY'
import ustd.common.utils

# Drive 4.x uses the LVM topology on UNAS. The UNVR and UNAS USTD payloads
# are byte-identical, but the physical UNVR hardware profile omits only the
# FEASSL capability. Add that capability to USD's in-process copy while
# preserving the UNVR's four-bay, thermal, fan and network mappings.
_physical_profile = ustd.common.utils.hardware.get("ea1a")
if not isinstance(_physical_profile, dict):
    raise RuntimeError("validated UNVR USTD hardware profile is unavailable")
_physical_features = _physical_profile.get("features")
if not isinstance(_physical_features, dict):
    raise RuntimeError("validated UNVR USTD feature map is unavailable")
_physical_features["FEASSL"] = True

import ustd.storage.disk

_disk_set_env_support_filesystem = ustd.storage.disk.Disk.set_env_support_filesystem
_disk_set_env_support_storage_layout = ustd.storage.disk.Disk.set_env_support_storage_layout

def _force_filesystem(_requested):
    return _disk_set_env_support_filesystem(["btrfs"])

def _force_storage_layout(_requested):
    return _disk_set_env_support_storage_layout(["raid", "lvm"])

ustd.storage.disk.Disk.set_env_support_filesystem = staticmethod(_force_filesystem)
ustd.storage.disk.Disk.set_env_support_storage_layout = staticmethod(_force_storage_layout)
_disk_set_env_support_filesystem(["btrfs"])
_disk_set_env_support_storage_layout(["raid", "lvm"])

import ustd.storage.volume

_opts_init = ustd.storage.volume.Volume.Opts.__init__
_opts_set_checksum = ustd.storage.volume.Volume.Opts.set_checksum
_opts_set_cow = ustd.storage.volume.Volume.Opts.set_cow

def _force_checksum(self, _requested):
    return _opts_set_checksum(self, True)

def _force_cow(self, _requested):
    return _opts_set_cow(self, True)

def _force_opts_init(self, *args, **kwargs):
    _opts_init(self, *args, **kwargs)
    _opts_set_checksum(self, True)
    _opts_set_cow(self, True)

ustd.storage.volume.Volume.Opts.set_checksum = _force_checksum
ustd.storage.volume.Volume.Opts.set_cow = _force_cow
ustd.storage.volume.Volume.Opts.__init__ = _force_opts_init
PY
    chmod 644 "$RUNTIME_ROOT/sitecustomize.py"
}

patch_drive_copy() {
    local source=$1 destination=$2 include_first_init=$3
    python3 - "$source" "$destination" "$include_first_init" <<'PY'
import os, sys
src, dst, include_first = sys.argv[1], sys.argv[2], sys.argv[3] == "yes"
with open(src, "rb") as handle:
    data = bytearray(handle.read())
patches = [
    (13826584, bytes.fromhex("010300b4"), bytes.fromhex("1f2003d5")),
    (13826620, bytes.fromhex("4d8ffd97"), bytes.fromhex("20008052")),
    (13827568, bytes.fromhex("900b40f9f10301d1"), bytes.fromhex("20008052c0035fd6")),
]
if include_first:
    patches.append((8530936, bytes.fromhex("e0079f9a"), bytes.fromhex("20008052")))
for offset, expected, replacement in patches:
    actual = bytes(data[offset:offset + len(expected)])
    if actual != expected:
        raise SystemExit("Drive patch source-byte validation failed")
    data[offset:offset + len(expected)] = replacement
temporary = dst + ".new"
with open(temporary, "wb") as handle:
    handle.write(data)
    handle.flush()
    os.fsync(handle.fileno())
os.chmod(temporary, 0o755)
os.replace(temporary, dst)
PY
}

compatibility_phase() {
    assert_base
    init_state
    if phase_done compatibility; then
        [[ -x "$RUNTIME_ROOT/load-btrfs.sh" && -f "$RUNTIME_ROOT/sitecustomize.py" ]] || die 'compatibility runtime files are missing'
        [[ -f /etc/systemd/system/unvr-unas-btrfs.service ]] || die 'Btrfs loader unit is missing'
        log 'storage compatibility phase already complete and present'
        return
    fi
    require_eq "$(sha /usr/share/unifi-drive/bin/unifi-drive)" "$DRIVE_ORIGINAL_HASH" 'official Drive binary changed'
    write_sitecustomize
    local compat="$RUNTIME_ROOT/unifi-drive-legacy-storage-compat"
    patch_drive_copy /usr/share/unifi-drive/bin/unifi-drive "$compat" yes

    cat > "$RUNTIME_ROOT/load-btrfs.sh" <<EOF
#!/bin/bash
set -Eeuo pipefail
[[ "\$(uname -r)" == "$EXPECTED_KERNEL" ]]
[[ "\$(sha256sum '$RUNTIME_ROOT/modules/$EXPECTED_KERNEL/zstd_compress.ko' | awk '{print \$1}')" == "$ZSTD_MODULE_HASH" ]]
[[ "\$(sha256sum '$RUNTIME_ROOT/modules/$EXPECTED_KERNEL/btrfs.ko' | awk '{print \$1}')" == "$BTRFS_MODULE_HASH" ]]
[[ "\$(sha256sum '$RUNTIME_ROOT/modules/$EXPECTED_KERNEL/fuse.ko' | awk '{print \$1}')" == "$FUSE_MODULE_HASH" ]]
grep -qw zstd_compress /proc/modules || insmod '$RUNTIME_ROOT/modules/$EXPECTED_KERNEL/zstd_compress.ko'
grep -qw btrfs /proc/modules || insmod '$RUNTIME_ROOT/modules/$EXPECTED_KERNEL/btrfs.ko'
grep -qw fuse /proc/modules || insmod '$RUNTIME_ROOT/modules/$EXPECTED_KERNEL/fuse.ko'
grep -qw btrfs /proc/filesystems
grep -qw fuse /proc/filesystems
for _ in \$(seq 1 20); do [[ -c /dev/fuse ]] && break; sleep 0.25; done
[[ -c /dev/fuse ]]
EOF
    chmod 755 "$RUNTIME_ROOT/load-btrfs.sh"
    cat > /etc/systemd/system/unvr-unas-btrfs.service <<EOF
[Unit]
Description=Load exact native Btrfs modules for UNVR Drive
DefaultDependencies=no
Requires=data.mount
After=data.mount systemd-modules-load.service
Before=usd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$RUNTIME_ROOT/load-btrfs.sh
EOF
    install -d -m 755 /etc/systemd/system/usd.service.d /etc/systemd/system/unifi-drive.service.d
    cat > /etc/systemd/system/usd.service.d/unvr-unas-btrfs.conf <<EOF
[Unit]
Requires=unvr-unas-btrfs.service
After=unvr-unas-btrfs.service

[Service]
Environment=PYTHONPATH=$RUNTIME_ROOT
EOF
    cat > /etc/systemd/system/unifi-drive.service.d/unvr-unas-compat.conf <<EOF
[Service]
ExecStart=
ExecStart=$compat -c /usr/share/unifi-drive/config/config.json
EOF
    printf '%s\n' '{"max_raid_size":0,"max_volume_size":0,"max_num_volume":1,"prefer_raid":"raid5","filesystem":"btrfs","hotspare":false,"automode":true}' > /etc/ustd/storage.conf
    systemctl daemon-reload
    systemctl enable unvr-unas-btrfs.service >/dev/null
    systemctl restart unvr-unas-btrfs.service
    PYTHONPATH="$RUNTIME_ROOT" python3 - <<'PY'
from ustd.common.utils import check_lvm_enabled, load_hardware_config
from ustd.storage.disk import Disk
from ustd.storage.volume import Volume
assert load_hardware_config()["features"]["FEASSL"] is True
assert check_lvm_enabled() is True
Disk.set_env_support_storage_layout(["raid"])
assert Disk._SUPPORT_STORAGE_LAYOUT == ["raid", "lvm"]
o = Volume.Opts()
o.set_checksum(False)
o.set_cow(False)
assert o.list_mount_opts("btrfs") == ["relatime", "space_cache=v2", "datacow", "datasum"]
PY
    systemctl restart usd.service
    PYTHONPATH="$RUNTIME_ROOT" python3 - <<'PY'
import threading, time
from ustd.statusdb.sdb_client import SDBClient
c = SDBClient()
threading.Thread(target=c.run, daemon=True).start()
deadline = time.time() + 30
while time.time() < deadline:
    root = c.get(None, {})
    if isinstance(root, dict) and "system" in root:
        break
    time.sleep(.25)
else:
    raise SystemExit("USTD status database did not become ready")
system = dict(root["system"])
features = dict(system.get("features", {}))
features["WASD"] = True
system["features"] = features
c.update("system", system)
time.sleep(1)
assert c.get(None, {})["system"]["features"]["WASD"] is True
PY
    mark_done compatibility
    log 'Btrfs, COW, checksum and one-disk compatibility active'
}

install_profile_file() {
    local source=$1 target=$2 mode=$3 current
    [[ -f "$source" && ! -L "$source" ]] || die "profile payload file missing or unsafe: ${source##*/}"
    [[ ! -L "$target" && ( ! -e "$target" || -f "$target" ) ]] \
        || die "profile target is not a safe regular file: $target"
    if [[ -f "$target" ]]; then
        current=$(sha "$target")
        [[ "$current" == "$(sha "$source")" ]] || die "refusing to overwrite an unrecognized profile artifact: $target"
        chown root:root "$target"
        chmod "$mode" "$target"
        return
    fi
    install -d -m 755 "$(dirname "$target")"
    install -o root -g root -m "$mode" "$source" "$target"
    require_eq "$(sha "$target")" "$(sha "$source")" "profile artifact copy failed: $target"
}

refresh_profile_file() {
    local source=$1 target=$2 mode=$3
    shift 3
    local desired current allowed tmp recognized=false
    [[ -f "$source" && ! -L "$source" ]] || die "refreshed profile source is missing or unsafe: ${source##*/}"
    [[ -f "$target" && ! -L "$target" ]] || die "refreshed profile target is missing or unsafe: $target"
    desired=$(sha "$source")
    current=$(sha "$target")
    if [[ "$current" == "$desired" ]]; then
        chown root:root "$target"
        chmod "$mode" "$target"
        return
    fi
    for allowed in "$@"; do
        if [[ "$current" == "$allowed" ]]; then
            recognized=true
            break
        fi
    done
    [[ "$recognized" == true ]] || die "refusing to refresh an unrecognized profile artifact: $target"
    tmp=$(mktemp "${target}.refresh.XXXXXX")
    install -o root -g root -m "$mode" "$source" "$tmp"
    require_eq "$(sha "$tmp")" "$desired" "refreshed profile artifact copy failed: $target"
    mv -f "$tmp" "$target"
}

validate_identity_dependencies_5x() {
    local unit dropin
    for unit in unifi-core.service ulp-go.service uid-agent.service; do
        dropin="/etc/systemd/system/$unit.d/unvr-unas-identity.conf"
        [[ -f "$dropin" && ! -L "$dropin" ]] || die "identity dependency is missing or unsafe: $unit"
        grep -qx 'Requires=unvr-unas-identity-restore.service' "$dropin" \
            || die "identity dependency requirement is invalid: $unit"
        grep -qx 'After=unvr-unas-identity-restore.service' "$dropin" \
            || die "identity dependency ordering is invalid: $unit"
    done
}

reconcile_identity_services_5x() {
    local deadline unit ready
    systemctl reset-failed unvr-unas-identity-restore.service uid-agent.service ulp-go.service unifi-core.service >/dev/null 2>&1 || true
    systemctl restart unvr-unas-identity-restore.service uid-agent.service ulp-go.service unifi-core.service >/dev/null 2>&1 || true
    deadline=$((SECONDS + 180))
    while (( SECONDS < deadline )); do
        ready=true
        for unit in unvr-unas-identity-restore uid-agent ulp-go unifi-core; do
            systemctl is-active --quiet "$unit" || ready=false
        done
        if [[ "$ready" == true ]] && curl -ksSf https://127.0.0.1/api/system >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    for unit in unvr-unas-identity-restore uid-agent ulp-go unifi-core; do
        systemctl is-active --quiet "$unit" || die "$unit did not recover after identity reconciliation"
    done
    die 'Core API did not recover after identity reconciliation'
}

ensure_identity_dependencies_5x() {
    local unit dir dropin tmp
    for unit in unifi-core.service ulp-go.service uid-agent.service; do
        dir="/etc/systemd/system/$unit.d"
        dropin="$dir/unvr-unas-identity.conf"
        install -d -m 755 "$dir"
        tmp=$(mktemp "$dir/.unvr-unas-identity.XXXXXX")
        printf '[Unit]\nRequires=unvr-unas-identity-restore.service\nAfter=unvr-unas-identity-restore.service\n' > "$tmp"
        chmod 644 "$tmp"
        mv -f "$tmp" "$dropin"
    done
    validate_identity_dependencies_5x
}

direct_5x_profile_phase() {
    assert_base_5_runtime
    init_state
    phase_done backup || die 'clean 5.1 backup phase is incomplete'
    phase_done update-guard || die 'automatic-update guard phase is incomplete'
    phase_done dedicated-guard || die 'Protect guard phase is incomplete'
    phase_done modules || die 'native module phase is incomplete'
    require_prestorage_blank_state
    local expected_bundle=${1:-} bundle="$STATE_ROOT/update-profiles.tar.gz"
    [[ "$expected_bundle" =~ ^[0-9a-f]{64}$ ]] || die 'profile bundle SHA-256 is required'
    [[ -f "$bundle" && ! -L "$bundle" ]] || die 'profile bundle is missing or unsafe'
    require_eq "$(sha "$bundle")" "$expected_bundle" 'profile bundle hash mismatch'
    local stage="$STATE_ROOT/direct-5x-profile-stage" member source
    [[ ! -L "$STATE_ROOT/direct-profile-in-progress" ]] || die 'direct-profile progress marker is unsafe'
    : > "$STATE_ROOT/direct-profile-in-progress"
    chmod 600 "$STATE_ROOT/direct-profile-in-progress"
    rm -rf -- "$stage"
    install -d -m 700 "$stage"
    while IFS= read -r member; do
        [[ "$member" != /* && "$member" != ../* && "$member" != */../* ]] \
            || die 'unsafe path in update profile bundle'
    done < <(tar -tzf "$bundle")
    tar -xzf "$bundle" -C "$stage" --no-same-owner
    (cd "$stage" && sha256sum -c SHA256SUMS >/dev/null) \
        || die 'profile payload manifest failed'
    if phase_done direct-5x-profile; then
        install_profile_file "$stage/profiles/5.1.33/core-service.js" "$RUNTIME_ROOT/profiles/5.1.33/core-service.js" 0644
        refresh_profile_file "$stage/ensure-unas-identity" "$RUNTIME_ROOT/ensure-unas-identity" 0755 \
            f423015b9ce266499c97018a83ffaf3ac6c25c14aec21f87229f3a9ebfeef963 \
            16a31219ed346dd3449f5700d7b9f67a62c59f1957e67a57de2beeb2311ecb32 \
            436da998ac636d321ad9caa6ddfb846a08113f40f8b3df81953884889ae6f17e \
            39386999837fc5bb955fc6eadc20435277809920216c4d2ccc35480faf911003 \
            e54e4dc5e6db1a4f436e3e1e29b2210b9f171422b37366959e4e8e19c7b279a0 \
            dc74bb80e08265448bed0cec38594720c68b45643d02fe925bee853fa3e28d75 \
            a7428f82f05d8ed0484e355a6a6e01ea129dc364517caaacaf1cee218c217f5c \
            affad526f2ad18a7bd65d7a92d47f561d48b0254c98d14f825cdcc28e92627b7 \
            3bceab6c9c3422d91a5f9ed3cc2b6c1882c1812ff47035ace2f4f85da3640b21 \
            133efb78dc335be743d998a65c71ce813a6f629b6d46742f155ea53319f78b6a \
            def43759045b813e7d84c379e706c6e589570c65d7f1f67fb91969b6670ae7f8
        refresh_profile_file "$stage/restore-drive-after-base-update" "$RUNTIME_ROOT/restore-drive-after-base-update" 0755 \
            ac99866d89f244e800615c675f37438b5ac14d28cc89d399f1abb2e2805b6a5b \
            6c938528bebc32a4bcb3ee09a73e4f2f1eacee34c9e0d59f473175be2e141fc8 \
            db25fcc9f2ac59bd5ddf8c9b0c5eb3b0b88267b1c359f920f90ece02f8a62997 \
            a39d6d8bbc451a253030058f80b5183884b99b692c21ea36d64e5254faa5581f \
            4f7753cad206e083482cce9ddef64d68d779047032df49a7a92cbca3e29be7cb \
            c0a3f2b583ba404c6d7194e14f54855a40c920709e56dadffa1fedcd8b7c9057 \
            cf7835265a732ee1b40e7bf4f98b60c45e36ba4fffa71cc9c3064d012355a679 \
            8c424361ec71edbd378cba91de90b27e7155bd6ca1f913f41a4584a6d6a079e4 \
            d36804e9193e20be5ade982499688193af55551a491c548c49c8656514f867ba \
            4b0ef0db70d46465008376cb319e439836ee0003257f4ff5eb84b58b290dbb77 \
            e546d1f0390af0ff4bc98f978176aece5a8a562a619743cfed456c61408ff8bc \
            c50a7b8e37013338f1c0aa010bc0ad4b69e0f21a0d81ec7122770d80210d24f5
        refresh_profile_file "$stage/unifi-drive-launcher" "$RUNTIME_ROOT/unifi-drive-launcher" 0755 \
            b7041bcf52b01ffa1b8f7f963a26817bdcbe109c967498721679d88b3623c141
        refresh_profile_file "$stage/query-drive-storage-state" "$RUNTIME_ROOT/query-drive-storage-state" 0644 \
            f018cd1a7c4c6dc55937c2d2d088fe48920de395baa3fb82987e7e72797a60af
        refresh_profile_file "$stage/tools/build_5x_identity_overlays.py" "$RUNTIME_ROOT/tools/build_5x_identity_overlays.py" 0644 \
            f426be325c5cab765d72f28c212bf0a0649223c2198f6c86ac3b59b75041f8ab
        refresh_profile_file "$stage/guarded-fwupdate" "$RUNTIME_ROOT/guarded-fwupdate" 0755 \
            3efb50943a47a9a7c39ff6f320732568286b417993779953aef7255532e8818d \
            90113a7eccf8387e456423515cb6e57ebd4fc2e2a699783f32d64cd16bbc84b8 \
            57a2fcbd496f036267300b6b960660654983bd49ec524fb7a3d43a92508642da \
            db9cf67f92e0ba847f55bab349394a52aa122b42a993dd9d0eae78c2e7054e44 \
            aab3f86cda3e391fee094ad673db408f5f6f9d4cb283ea3bd24340a745b603d2 \
            3b3c78671ff7f3821ba3c861b4adc230935c0fbcdc1c3c0e20fabe2c5caeb98b \
            527915ec8356fd8ebd6312aa8458207714b43ac3797ac3d66f6319902b1cf0a8 \
            2be402f3111f59848ae3334595f5c44ee586de14155d2fa9ebe003ddf9d85bbf \
            9bf20e69ba3430be1201dc31b7924966cc3fea6a8e6c5a9628e2466a8f109489 \
            1564053141526b2a20eb9fdbe0c7aa1292ed2e17dde99a9c710a74191d88ffaa \
            2ee21523567ba4b51dd2a1b21ddd7e18a40dee90e9535a8de8757672b72caad5 \
            5392363e122bedfd7d97012c5f88a15d22210f5f8bbf5ba9c8a9188860a23c7b \
            596f8ab119194dc1c55bab1811a7526365c832e06a5a42c0794b6a1a7cc0e850 \
            cf5d1d95860e72c88c8858813117debf29ae701983fe541669dcd0add964dc24 \
            3e7007a890ba2db017fe6a1ff44f0459a2469ea05e217de43f22dfbfd29c5fe0 \
            0ba604709e85a6a695dfbad3a8dbd8f5c4caf6ff6e0d9361bae4d97b2ec30945 \
            aca5d0158c13d87cf514a1f207e2133b53ee503208f7ddc8350aba9d39f50cc1 \
            82da9ffd8368ae277c1a7d3dd08b67e048acbafd13c0b11fbbd77d0a146ea5fc \
            069430b8b381e16b42a7b1c24ec4d0a3d6c9bb32cfd765b7c83c7cfc78083ce5 \
            264891ddfe60bb3f3ed9e2ed690cd5fe831ca6729063ea772a6b3d3a0287d003 \
            701a1f4082d7fbceec60cb64d50acaa0b8a448289c42722d066b835c18d29644 \
            701679577e48395a03e75c47a028154aed1d40b93a70b87270325877aac2bfb8 \
            b70b8ec75914b44c74ec511c65d796851a503384682300b39ff83b6039190561 \
            5bd2c0ba44a2dd330c2d7d36bb48565055cde1c927cd1290348ca71a3244ea66 \
            5554f3ad5ebc2bbbfc12c06ec18485c8da2e35eeb7bcfd824069bfc39a23791c \
            409a9e2a1795a8b3b9d85765e414662895474a0fead191b3a5c5d6f6e09ff0a7 \
            f3c2fab7260eebd1d030e13de785d75571c2b4bcc93ec551404dc03b54e94259
        refresh_profile_file "$stage/logical-unadopt" "$RUNTIME_ROOT/logical-unadopt" 0755 \
            4fa0e693bfb5a0159c99b7161e929e33b08350400265663495db1ddb4a874575 \
            81e5fcb4a89a7dff396e723c04ac3409ef9cfb7eedf054d8def033072bc04fde \
            a773ad9bc7a7adaec695464731705f1c6e4eb0caca5c9046249e7bd2a0299db2 \
            5f41df4e1810874c7f17368bd1f8ffd193c4870cde841c548f6af1d0f4a9014f \
            4783554f265e7653bfd8ab275012ccb00373c4c107edc6d6938fc280ef449672
        refresh_profile_file "$stage/readopt-ssh-restorer" "$RUNTIME_ROOT/readopt-ssh-restorer" 0755 \
            b56f3a79333ad8722580a084979bd50f3289302e9b3a1fc7a7b9ca47704ffd72 \
            3953a0195a021da2059fb0c504e6800d82fa4b7b9c4f67c866e438f9b18d3e86 \
            dac1bcab5d2785a49b2b30a7b1d53b342b8a40c9539a7b29016fb34e6abe032d \
            eb56464ec82ac79824f884edb18d2299e10c0452b8ec83ba4890917ed77642ba \
            c519104a5e9df934e48c677cdfb67938577e85450fbe5499a682be3d31cd4a72 \
            c17c4f3222ec89f18a618f219ef18dc307ce13ebb078407d071f75d51d7e81b8 \
            97caf5292d2dfd68df9796b099762bbf5a7fff5555c0bec7c61807e9fb3165ef \
            3f5be0348a3822f987d633ded6a1a28fe0d1a1a9292170b05eedc8d95c47def7 \
            dab140747a4fd5e02baf96a5a624b7547daa7b69785019ddfb6de570c8870030 \
            6b4f88cc8fbefab01b0826b5f2752635b5216cb5ca341b09a5cf3eedb78096a3 \
            07b31f67ae72d64e5e607ecc5f2477c17dc90eade4779c65934e7946b24d0f98 \
            e78e5b023ea847c5933b255200b9e8957515193de6e5b260350d803bf84ea161 \
            213382af5a41aa9edd7f1c322e7b7adb560ebfa920435ad89e67e3caa7cd7647 \
            34f864421bef29a011b244ae732329cdad4099bf655297f2d16e84565bd85da4 \
            400cdf7d2c793ee5c708c84586c92dd6783f1806b153ae99480e1c5554c34df5 \
            facaf5882eb9677596496f007b62a47957bd5fe21173d25402b704b67f49e863
        if [[ -f "$RUNTIME_ROOT/drive-bin/ubnt-tools" ]]; then
            refresh_profile_file "$stage/unifi-drive-ubnt-tools" "$RUNTIME_ROOT/drive-bin/ubnt-tools" 0755 \
                0399c66d814973f4c3c65f6eb939de865317ba51a697595d0d8f00d32b407809 \
                d263945d1827e17035940b8001d9f9b8413d8cfa90636b2cb3eb63f437ead824 \
                d2d0f7da32730a03f512f849c6412da083705ef2539d0d0e359cf53b4b9c00cc
        else
            install_profile_file "$stage/unifi-drive-ubnt-tools" "$RUNTIME_ROOT/drive-bin/ubnt-tools" 0755
        fi
        refresh_profile_file "$stage/unvr-unas-readopt-ssh.service" /etc/systemd/system/unvr-unas-readopt-ssh.service 0644 \
            8bb1391aa93910c17b492944a099b60d1b6e5b2d75b97b47c2facbb66f559c28 \
            15b321736e8d591b152932178bf369ce3c2ced0cc1470eb985f395157911d1ae \
            aaeaab8305839b30a2dad9384d16c55290ac1eba35b32ac00d7ae22de8ba0208
        refresh_profile_file "$stage/unvr-unas-drive-restore.service" /etc/systemd/system/unvr-unas-drive-restore.service 0644 \
            4fc55ee7a42102f881234530b8201d9c93101ab074f362f066d00bdc257742ac
        install_immutable_dependency_payload_5x "$stage"
        ensure_identity_dependencies_5x
        systemctl daemon-reload
        printf '%s\n' "$PAYLOAD_VERSION" > "$RUNTIME_ROOT/installer-payload-version"
        chmod 600 "$RUNTIME_ROOT/installer-payload-version"
        ensure_drive_scoped_identity_5x
        "$RUNTIME_ROOT/ensure-unas-identity"
        reconcile_identity_services_5x
        validate_direct_profile_resume_5x
        rm -rf -- "$stage"
        rm -f -- "$bundle"
        rm -f -- "$STATE_ROOT/direct-profile-in-progress"
        log 'direct 5.1 UNAS profile is already installed and verified'
        return
    fi

    for source in \
        profiles/5.1.33/core-service.js \
        profiles/5.1.33/uid-unifi-os-consoles.json \
        profiles/5.1.33/ulp-unifi-os-console.json \
        profiles/5.1.33/uhd-setup-index.template.html \
        profiles/5.1.33/portal-index.template.html \
        profiles/5.1.33/unifi-assets.tar.gz; do
        install_profile_file "$stage/$source" "$RUNTIME_ROOT/$source" 0644
    done
    for source in build_core_unaspro_identity_patch.js build_core_5x_unaspro_patch.js build_5x_identity_overlays.py patch_portal_unaspro_manifest.js verify_storage_ui_contract.js; do
        install_profile_file "$stage/tools/$source" "$RUNTIME_ROOT/tools/$source" 0644
    done
    install_profile_file "$stage/query-drive-storage-state" "$RUNTIME_ROOT/query-drive-storage-state" 0644
    install_profile_file "$stage/packages/wsdd_0.8.deb" "$RUNTIME_ROOT/packages/wsdd_0.8.deb" 0600
    install_profile_file "$stage/packages/wsdd-server_0.8.deb" "$RUNTIME_ROOT/packages/wsdd-server_0.8.deb" 0600
    install_immutable_dependency_payload_5x "$stage"
    install_profile_file "$stage/ensure-unas-identity" "$RUNTIME_ROOT/ensure-unas-identity" 0755
    install_profile_file "$stage/restore-drive-after-base-update" "$RUNTIME_ROOT/restore-drive-after-base-update" 0755
    install_profile_file "$stage/unifi-drive-launcher" "$RUNTIME_ROOT/unifi-drive-launcher" 0755
    install_profile_file "$stage/unifi-drive-ubnt-tools" "$RUNTIME_ROOT/drive-bin/ubnt-tools" 0755
    install_profile_file "$stage/guarded-fwupdate" "$RUNTIME_ROOT/guarded-fwupdate" 0755
    install_profile_file "$stage/logical-unadopt" "$RUNTIME_ROOT/logical-unadopt" 0755
    install_profile_file "$stage/readopt-ssh-restorer" "$RUNTIME_ROOT/readopt-ssh-restorer" 0755
    install_profile_file "$stage/unvr-unas-identity-restore.service" /etc/systemd/system/unvr-unas-identity-restore.service 0644
    install_profile_file "$stage/unvr-unas-drive-restore.service" /etc/systemd/system/unvr-unas-drive-restore.service 0644
    install_profile_file "$stage/unvr-unas-readopt-ssh.service" /etc/systemd/system/unvr-unas-readopt-ssh.service 0644

    local recovery_dir="$RUNTIME_ROOT/recovery" kernel_mount=/run/unvr-unas-direct-kernel-read rootfs_mount=/run/unvr-unas-direct-rootfs-read
    local backup_kernel_hash backup_rootfs_hash backup_rootfs_version
    install -d -m 700 "$recovery_dir" "$kernel_mount" "$rootfs_mount"
    ! mountpoint -q "$kernel_mount" || die 'recovery-kernel validation mount point is already in use'
    mount -o ro /dev/boot1 "$kernel_mount"
    trap 'mountpoint -q /run/unvr-unas-direct-kernel-read && umount /run/unvr-unas-direct-kernel-read || true' RETURN EXIT HUP INT TERM
    require_eq "$(sha "$kernel_mount/uImage")" 158688310a8fbef461c2f72a1d05326a246bcfa8525e3dc77177454853c462da 'active signed 5.1.33 kernel hash mismatch'
    [[ -f "$kernel_mount/uImage.bkp" ]] || die 'stock updater predecessor kernel backup is missing'
    [[ "$(stat -c %s "$kernel_mount/uImage.bkp")" -gt 5242880 ]] \
        || die 'stock updater predecessor kernel backup is implausibly small'
    require_eq "$(head -c 4 "$kernel_mount/uImage.bkp" | od -An -tx1 | tr -d ' \n')" 27051956 \
        'stock updater predecessor kernel backup is not a U-Boot image'
    backup_kernel_hash=$(sha "$kernel_mount/uImage.bkp")
    [[ "$backup_kernel_hash" =~ ^[0-9a-f]{64}$ ]] || die 'stock updater predecessor kernel hash is invalid'
    install -o root -g root -m 0600 "$kernel_mount/uImage" "$recovery_dir/uImage-5.1.33"
    install -o root -g root -m 0600 "$kernel_mount/uImage.bkp" "$recovery_dir/uImage-source.bkp"
    printf '%s\n' "$backup_kernel_hash" > "$recovery_dir/uImage-source.bkp.sha256"
    chmod 0600 "$recovery_dir/uImage-source.bkp.sha256"
    require_eq "$(sha "$recovery_dir/uImage-5.1.33")" 158688310a8fbef461c2f72a1d05326a246bcfa8525e3dc77177454853c462da '5.1.33 recovery kernel copy mismatch'
    require_eq "$(sha "$recovery_dir/uImage-source.bkp")" "$backup_kernel_hash" 'source recovery kernel copy mismatch'
    umount "$kernel_mount"
    trap - RETURN EXIT HUP INT TERM

    [[ -f /boot/firmware/rootfs.bkp && ! -L /boot/firmware/rootfs.bkp ]] \
        || die 'stock updater predecessor rootfs backup is missing or unsafe'
    require_eq "$(head -c 4 /boot/firmware/rootfs.bkp | od -An -tx1 | tr -d ' \n')" 68737173 \
        'stock updater predecessor rootfs backup is not SquashFS'
    ! mountpoint -q "$rootfs_mount" || die 'source-rootfs validation mount point is already in use'
    mount -o ro,loop /boot/firmware/rootfs.bkp "$rootfs_mount"
    trap 'mountpoint -q /run/unvr-unas-direct-rootfs-read && umount /run/unvr-unas-direct-rootfs-read || true' RETURN EXIT HUP INT TERM
    backup_rootfs_version=$(cat "$rootfs_mount/usr/lib/version" 2>/dev/null || true)
    [[ "$backup_rootfs_version" == UNVR4.al324.v* ]] \
        || die 'stock updater predecessor rootfs is not a UNVR image'
    umount "$rootfs_mount"
    trap - RETURN EXIT HUP INT TERM
    backup_rootfs_hash=$(sha /boot/firmware/rootfs.bkp)
    printf '%s\n' "$backup_rootfs_hash" > "$recovery_dir/rootfs-source.bkp.sha256"
    printf '%s\n' "$backup_rootfs_version" > "$recovery_dir/rootfs-source.bkp.version"
    chmod 0600 "$recovery_dir/rootfs-source.bkp.sha256" "$recovery_dir/rootfs-source.bkp.version"
    require_eq "$(sha /boot/firmware/rootfs.bkp)" "$backup_rootfs_hash" 'source recovery rootfs changed while recording'

    printf '%s\n' 5.1.33 > "$RUNTIME_ROOT/logical-target"
    printf '%s\n' "$PAYLOAD_VERSION" > "$RUNTIME_ROOT/installer-payload-version"
    chmod 600 "$RUNTIME_ROOT/installer-payload-version"
    : > "$RUNTIME_ROOT/enabled"
    rm -f -- "$RUNTIME_ROOT/allow-base-update-4.3.10" \
        "$RUNTIME_ROOT/allow-userspace-update-5.1.33" "$RUNTIME_ROOT/allow-base-update-5.1.33"
    ensure_identity_dependencies_5x
    systemctl daemon-reload
    systemctl enable unvr-unas-identity-restore.service >/dev/null
    systemctl disable unvr-unas-drive-restore.service >/dev/null 2>&1 || true
    ensure_drive_scoped_identity_5x
    "$RUNTIME_ROOT/ensure-unas-identity"
    reconcile_identity_services_5x
    require_eq "$(sha /usr/share/unifi-core/app/node_modules/@ubnt/uhd-setup/dist/index.html)" cff883330a7bb3ab378053ddd9611f22efea8a4ff22863f9cfd59aeda0fa831c 'Core did not generate the official UNAS setup manifest'
    require_eq "$(sha /usr/share/unifi-core/app/node_modules/@ubnt/unifi-portal/dist/local/index.html)" 8e81c708d68c18385139422d1ab34d95a2d5a4a538d47797db2c8d15a6542d1c 'Core did not generate the official UNAS portal manifest'
    rm -rf -- "$stage"
    rm -f -- "$bundle"
    mark_done direct-5x-profile
    rm -f -- "$STATE_ROOT/direct-profile-in-progress"
    log 'direct 5.1 scoped UNAS identity and recovery payload installed'
}

drive_samba_config_semantically_valid() {
    local config=$1 value
    [[ -f "$config" && ! -L "$config" ]] || return 1
    command -v testparm >/dev/null 2>&1 || return 1
    testparm -s --suppress-prompt "$config" >/dev/null 2>&1 || return 1
    [[ "$(grep -Ec '^[[:space:]]*\[global\][[:space:]]*$' "$config")" == 1 ]] || return 1
    grep -Eiq '^[[:space:]]*security[[:space:]]*=[[:space:]]*user[[:space:]]*$' "$config" || return 1
    grep -Eiq '^[[:space:]]*map to guest[[:space:]]*=[[:space:]]*never[[:space:]]*$' "$config" || return 1
    grep -Eiq '^[[:space:]]*allow insecure wide links[[:space:]]*=[[:space:]]*no[[:space:]]*$' "$config" || return 1
    grep -Eiq '^[[:space:]]*follow symlinks[[:space:]]*=[[:space:]]*no[[:space:]]*$' "$config" || return 1
    grep -Eiq '^[[:space:]]*passdb backend[[:space:]]*=[[:space:]]*tdbsam:/etc/samba/private/passdb\.tdb[[:space:]]*$' "$config" || return 1
    grep -Eiq '^[[:space:]]*dfree command[[:space:]]*=[[:space:]]*/usr/sbin/dfree[[:space:]]*$' "$config" || return 1
    grep -Eiq '^[[:space:]]*include[[:space:]]*=[[:space:]]*/etc/samba/share\.conf[[:space:]]*$' "$config" || return 1
    grep -Eiq '^[[:space:]]*\[Personal-Drive\][[:space:]]*$' "$config" || return 1
    grep -Eiq '^[[:space:]]*path[[:space:]]*=[[:space:]]*%H/\.data[[:space:]]*$' "$config" || return 1
    grep -Eiq '^[[:space:]]*valid users[[:space:]]*=[[:space:]]*@unifi-drive[[:space:]]*$' "$config" || return 1
    grep -Eiq '^[[:space:]]*\[unifi-drive-backup-only\][[:space:]]*$' "$config" || return 1
    while IFS= read -r value; do
        value=$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$value" in
            /etc/samba/share.conf|/etc/samba/userconfig.d/shadow-share-%U.conf) ;;
            *) return 1 ;;
        esac
    done < <(awk -F= 'tolower($1) ~ /^[[:space:]]*include[[:space:]]*$/ {print $2}' "$config")
}

recover_drive_samba_config_5x() (
    local candidate deb package version tmp
    for candidate in /etc/samba/smb.conf.dpkg-new /etc/samba/smb.conf.dpkg-dist; do
        if drive_samba_config_semantically_valid "$candidate"; then
            install -o root -g root -m 0644 "$candidate" /etc/samba/smb.conf.new
            mv -f /etc/samba/smb.conf.new /etc/samba/smb.conf
            return 0
        fi
    done
    tmp=$(mktemp /etc/samba/.smb.conf.unvr-recovery.XXXXXX)
    trap 'rm -f -- "$tmp"' EXIT HUP INT TERM
    while IFS= read -r deb; do
        package=$(dpkg-deb -f "$deb" Package 2>/dev/null || true)
        version=$(dpkg-deb -f "$deb" Version 2>/dev/null || true)
        [[ "$package" == unifi-drive-config && "$version" == 2.23.0-11+ga8a43c45ecd7 ]] || continue
        dpkg-deb --fsys-tarfile "$deb" | tar -xOf - ./etc/samba/smb.conf > "$tmp"
        if drive_samba_config_semantically_valid "$tmp"; then
            install -o root -g root -m 0644 "$tmp" /etc/samba/smb.conf.new
            mv -f /etc/samba/smb.conf.new /etc/samba/smb.conf
            rm -f -- "$tmp"
            trap - EXIT HUP INT TERM
            return 0
        fi
    done < <(find /data/uos/downloads /var/cache/apt/archives -maxdepth 1 -type f -name '*.deb' -print 2>/dev/null)
    return 1
)

validate_drive_dependency_group_5x() {
    local package
    validate_stock_unas_apt_policy
    require_eq "$(pkg_version unifi-drive)" 4.3.10 'Drive version mismatch'
    require_eq "$(pkg_version unifi-drive-config)" 2.23.0-11+ga8a43c45ecd7 'Drive Config version mismatch'
    require_eq "$(pkg_version unifi-drive-rclone)" 1.74.4-1+g2b3bd0b0f35e 'Drive rclone version mismatch'
    for package in samba samba-common samba-common-bin samba-libs samba-vfs-modules; do
        require_eq "$(pkg_version "$package")" "$EXPECTED_SAMBA_5_VERSION" "Samba dependency version mismatch: $package"
    done
    require_eq "$(pkg_version btrfs-progs)" "$EXPECTED_BTRFS_PROGS_VERSION" 'btrfs-progs version mismatch'
    require_eq "$(pkg_version nfs-kernel-server)" "$EXPECTED_NFS_VERSION" 'NFS server version mismatch'
    require_eq "$(pkg_version nfs-common)" "$EXPECTED_NFS_VERSION" 'NFS common version mismatch'
    require_eq "$(pkg_version fuse3)" "$EXPECTED_FUSE3_VERSION" 'FUSE userspace version mismatch'
    require_eq "$(pkg_version lvm2)" "$EXPECTED_LVM2_VERSION" 'LVM2 version mismatch'
    require_eq "$(pkg_version dmeventd)" "$EXPECTED_DM_EVENT_VERSION" 'LVM event daemon version mismatch'
    require_eq "$(pkg_version liblvm2cmd2.03:arm64)" "$EXPECTED_LVM2_VERSION" 'LVM command library version mismatch'
    require_eq "$(pkg_version libdevmapper-event1.02.1:arm64)" "$EXPECTED_DM_EVENT_VERSION" 'device-mapper event library version mismatch'
    require_eq "$(pkg_version thin-provisioning-tools)" "$EXPECTED_THIN_PROVISIONING_VERSION" 'thin-provisioning tools version mismatch'
    require_eq "$(pkg_version libaio1:arm64)" "$EXPECTED_LIBAIO_VERSION" 'LVM asynchronous-I/O library version mismatch'
    for package in \
        unifi-drive unifi-drive-config unifi-drive-rclone \
        samba samba-common samba-common-bin samba-libs samba-vfs-modules \
        btrfs-progs nfs-kernel-server nfs-common fuse3 wsdd wsdd-server \
        lvm2 dmeventd liblvm2cmd2.03:arm64 libdevmapper-event1.02.1:arm64 \
        thin-provisioning-tools libaio1:arm64; do
        pkg_configured "$package" || die "package is not fully configured: $package"
    done
    [[ -x /sbin/lvm && -L /sbin/pvcreate && -L /sbin/vgcreate && -L /sbin/lvcreate ]] \
        || die 'official UNAS LVM command layout is incomplete'
    require_eq "$(readlink /sbin/pvcreate)" lvm 'pvcreate link differs from the official UNAS layout'
    require_eq "$(readlink /sbin/vgcreate)" lvm 'vgcreate link differs from the official UNAS layout'
    require_eq "$(readlink /sbin/lvcreate)" lvm 'lvcreate link differs from the official UNAS layout'
    require_eq "$(sha /sbin/lvm)" "$EXPECTED_LVM_EXEC_HASH" 'LVM executable differs from the official UNAS image'
    require_eq "$(sha /usr/bin/wsdd)" a25263168006443c80ce55783af3630c2d75bdb349542f50493cf77d0ed24de2 'wsdd executable hash mismatch'
    DEBIAN_FRONTEND=noninteractive apt-get check >/dev/null \
        || die 'installed Drive dependency graph is inconsistent'
    [[ -f /etc/samba/smb.conf && ! -L /etc/samba/smb.conf ]] \
        || die 'official Drive Samba configuration is missing or unsafe'
    drive_samba_config_semantically_valid /etc/samba/smb.conf \
        || die 'official Drive Samba configuration failed its security and layout contract'
}

validate_drive_service_order_5x() {
    local dropin=/etc/systemd/system/unifi-drive.service.d/unvr-unas-compat.conf
    [[ -f "$dropin" && ! -L "$dropin" ]] || die 'Drive compatibility unit override is missing or unsafe'
    grep -qx 'Requires=unvr-unas-btrfs.service' "$dropin" \
        || die 'Drive does not require the native storage-module loader'
    grep -qx 'After=unvr-unas-btrfs.service' "$dropin" \
        || die 'Drive is not ordered after the native storage-module loader'
    grep -qx 'Requires=unvr-unas-identity-restore.service' "$dropin" \
        || die 'Drive does not require the scoped identity service'
    grep -qx 'After=unvr-unas-identity-restore.service' "$dropin" \
        || die 'Drive is not ordered after the scoped identity service'
    grep -qx "ExecStart=$RUNTIME_ROOT/unifi-drive-launcher -c /usr/share/unifi-drive/config/config.json" "$dropin" \
        || die 'Drive launcher override is invalid'
    grep -qx "Environment=PATH=$RUNTIME_ROOT/drive-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" "$dropin" \
        || die 'Drive-scoped identity PATH is invalid'
    grep -qx "BindReadOnlyPaths=$RUNTIME_ROOT/drive-bin/ubnt-tools:/sbin/ubnt-tools" "$dropin" \
        || die 'Drive-scoped absolute identity binding is invalid'
    grep -qx "BindReadOnlyPaths=$RUNTIME_ROOT/drive-system.info:/proc/ubnthal/system.info" "$dropin" \
        || die 'Drive-scoped system-information binding is invalid'
    require_eq "$(sha "$RUNTIME_ROOT/drive-bin/ubnt-tools")" 702081e0478f2cbdd0147caef1f0c21ce8600691b2c2d9c9910626cd555759a4 \
        'Drive-scoped ubnt-tools adapter mismatch'
    require_eq "$(sha "$RUNTIME_ROOT/drive-bin/real/ubnt-tools")" b158615d9ba1d21a31c29e923d3be23796c95c43cadea2b73e1ce1460e18058e \
        'Drive-scoped stock ubnt-tools pass-through mismatch'
}

ensure_drive_scoped_identity_5x() {
    local real="$RUNTIME_ROOT/drive-bin/real/ubnt-tools"
    require_eq "$(sha /sbin/ubnt-tools)" b158615d9ba1d21a31c29e923d3be23796c95c43cadea2b73e1ce1460e18058e \
        'stock ubnt-tools executable mismatch'
    if [[ -e "$real" ]]; then
        [[ -f "$real" && ! -L "$real" ]] || die 'Drive-scoped stock ubnt-tools pass-through is unsafe'
        require_eq "$(sha "$real")" b158615d9ba1d21a31c29e923d3be23796c95c43cadea2b73e1ce1460e18058e \
            'Drive-scoped stock ubnt-tools pass-through mismatch'
    else
        install -d -m 0755 "$RUNTIME_ROOT/drive-bin/real"
        install -o root -g root -m 0755 /sbin/ubnt-tools "$real"
        require_eq "$(sha "$real")" b158615d9ba1d21a31c29e923d3be23796c95c43cadea2b73e1ce1460e18058e \
            'Drive-scoped stock ubnt-tools pass-through copy failed'
    fi
}

verify_immutable_dependency_5x() {
    local file=$1 package=$2 version=$3 architecture=$4 size=$5 expected_hash=$6
    [[ -f "$file" && ! -L "$file" ]] || die "immutable dependency is missing or unsafe: $package"
    require_eq "$(stat -c %s "$file")" "$size" "immutable dependency size mismatch: $package"
    require_eq "$(sha "$file")" "$expected_hash" "immutable dependency SHA-256 mismatch: $package"
    require_eq "$(dpkg-deb -f "$file" Package)" "$package" "immutable dependency identity mismatch: $package"
    require_eq "$(dpkg-deb -f "$file" Version)" "$version" "immutable dependency version mismatch: $package"
    require_eq "$(dpkg-deb -f "$file" Architecture)" "$architecture" "immutable dependency architecture mismatch: $package"
}

immutable_dependency_manifests_5x() {
    printf '%s\n' "$RUNTIME_ROOT/debian-drive-closure.tsv" "$RUNTIME_ROOT/ubiquiti-drive-packages.tsv"
}

install_immutable_dependency_payload_5x() {
    local stage=$1 manifest filename package version architecture size expected_hash ignored source target
    require_eq "$(sha "$stage/debian-drive-closure.tsv")" "$DEBIAN_DRIVE_CLOSURE_SHA256" \
        'immutable Debian closure manifest mismatch'
    require_eq "$(sha "$stage/ubiquiti-drive-packages.tsv")" "$UBIQUITI_DRIVE_PACKAGES_SHA256" \
        'immutable Ubiquiti package manifest mismatch'
    if [[ -f "$RUNTIME_ROOT/debian-drive-closure.tsv" ]]; then
        refresh_profile_file "$stage/debian-drive-closure.tsv" "$RUNTIME_ROOT/debian-drive-closure.tsv" 0600 \
            51cf70007c34b68e9b410aa9dfc0e57f585b939b22b949382b2678228c6f2483
    else
        install_profile_file "$stage/debian-drive-closure.tsv" "$RUNTIME_ROOT/debian-drive-closure.tsv" 0600
    fi
    install_profile_file "$stage/ubiquiti-drive-packages.tsv" "$RUNTIME_ROOT/ubiquiti-drive-packages.tsv" 0600
    for manifest in "$stage/debian-drive-closure.tsv" "$stage/ubiquiti-drive-packages.tsv"; do
        while IFS=$'\t' read -r filename package version architecture size expected_hash ignored; do
            source="$stage/packages/$filename"
            verify_immutable_dependency_5x "$source" "$package" "$version" "$architecture" "$size" "$expected_hash"
            target="$RUNTIME_ROOT/packages/$filename"
            if [[ ! -f "$target" || "$(sha "$target")" != "$expected_hash" ]]; then
                install_profile_file "$source" "$target" 0600
            fi
            verify_immutable_dependency_5x "$target" "$package" "$version" "$architecture" "$size" "$expected_hash"
        done < "$manifest"
    done
}

cache_immutable_dependencies_5x() {
    local manifest filename package version architecture size expected_hash ignored source target tmp cache_version
    require_eq "$(sha "$RUNTIME_ROOT/debian-drive-closure.tsv")" "$DEBIAN_DRIVE_CLOSURE_SHA256" \
        'stored immutable Debian closure manifest mismatch'
    require_eq "$(sha "$RUNTIME_ROOT/ubiquiti-drive-packages.tsv")" "$UBIQUITI_DRIVE_PACKAGES_SHA256" \
        'stored immutable Ubiquiti package manifest mismatch'
    install -d -m 0755 /var/cache/apt/archives
    while IFS= read -r manifest; do
        while IFS=$'\t' read -r filename package version architecture size expected_hash ignored; do
            source="$RUNTIME_ROOT/packages/$filename"
            verify_immutable_dependency_5x "$source" "$package" "$version" "$architecture" "$size" "$expected_hash"
            cache_version=${version//:/%3a}
            target="/var/cache/apt/archives/${package}_${cache_version}_${architecture}.deb"
            if [[ ! -f "$target" || "$(sha "$target")" != "$expected_hash" ]]; then
                tmp=$(mktemp "/var/cache/apt/archives/.${package}.XXXXXX")
                install -o root -g root -m 0644 "$source" "$tmp"
                require_eq "$(sha "$tmp")" "$expected_hash" "immutable APT cache copy failed: $package"
                mv -f "$tmp" "$target"
            fi
            verify_immutable_dependency_5x "$target" "$package" "$version" "$architecture" "$size" "$expected_hash"
        done < "$manifest"
    done < <(immutable_dependency_manifests_5x)
}

install_immutable_dependency_group_5x() {
    local manifest filename package version architecture size expected_hash ignored cache_version
    local -a packages=()
    require_eq "$(sha "$RUNTIME_ROOT/debian-drive-closure.tsv")" "$DEBIAN_DRIVE_CLOSURE_SHA256" \
        'stored immutable Debian closure manifest mismatch'
    require_eq "$(sha "$RUNTIME_ROOT/ubiquiti-drive-packages.tsv")" "$UBIQUITI_DRIVE_PACKAGES_SHA256" \
        'stored immutable Ubiquiti package manifest mismatch'
    while IFS= read -r manifest; do
        while IFS=$'\t' read -r filename package version architecture size expected_hash ignored; do
            verify_immutable_dependency_5x "$RUNTIME_ROOT/packages/$filename" \
                "$package" "$version" "$architecture" "$size" "$expected_hash"
            cache_version=${version//:/%3a}
            packages+=("/var/cache/apt/archives/${package}_${cache_version}_${architecture}.deb")
        done < "$manifest"
    done < <(immutable_dependency_manifests_5x)
    cache_immutable_dependencies_5x
    DEBIAN_FRONTEND=noninteractive timeout 1800 apt-get install -y \
        --no-download --no-install-recommends "${packages[@]}" < /dev/null
}

validate_immutable_dependency_group_5x() {
    local manifest filename package version architecture size expected_hash ignored
    while IFS= read -r manifest; do
        while IFS=$'\t' read -r filename package version architecture size expected_hash ignored; do
            require_eq "$(pkg_version "$package")" "$version" "installed immutable package version mismatch: $package"
            pkg_configured "$package" || die "installed immutable package is not fully configured: $package"
        done < "$manifest"
    done < <(immutable_dependency_manifests_5x)
}

direct_5x_packages_phase() {
    assert_base_5_runtime
    init_state
    phase_done direct-5x-profile || die 'direct 5.1 profile phase is incomplete'
    require_eq "$(cat "$RUNTIME_ROOT/installer-payload-version" 2>/dev/null || true)" "$PAYLOAD_VERSION" \
        'current installer payload was not reconciled before package installation'
    validate_identity_dependencies_5x
    require_prestorage_blank_state
    ensure_drive_scoped_identity_5x
    if phase_done packages && phase_done compatibility; then
        validate_drive_dependency_group_5x
        validate_drive_service_order_5x
        require_eq "$(sha /usr/share/unifi-drive/bin/unifi-drive)" b26ed8c0e33bd44a6daf83b2b123513c231665161a9a2b2a70bd852bf5bd4b0a 'official Drive executable drifted'
        jq -e '.filesystem == ["btrfs"] and .automode == true and .setup == false' /etc/ustd/storage.conf >/dev/null \
            || die 'pre-storage USTD configuration drifted'
        require_prestorage_blank_state
        [[ -f "$RUNTIME_ROOT/prestorage-block-usd" ]] || die 'pre-storage USD guard marker is missing'
        grep -qx "ConditionPathExists=!$RUNTIME_ROOT/prestorage-block-usd" /etc/systemd/system/usd.service.d/unvr-unas-prestorage.conf \
            || die 'pre-storage USD guard drop-in is invalid'
        ! systemctl is-active --quiet usd.service || die 'usd is active before UNAS onboarding'
        for unit in uid-agent unifi-drive unvr-unas-btrfs; do
            systemctl is-active --quiet "$unit" || die "$unit is not active in completed package phase"
        done
        log 'direct 5.1 Drive packages and compatibility are already verified'
        return
    fi

    require_free_bytes / 1073741824 'the official Drive dependency group'

    local module_dir="$RUNTIME_ROOT/modules/$EXPECTED_KERNEL"
    require_eq "$(sha "$module_dir/zstd_compress.ko")" "$ZSTD_MODULE_HASH" 'native zstd module mismatch'
    require_eq "$(sha "$module_dir/btrfs.ko")" "$BTRFS_MODULE_HASH" 'native Btrfs module mismatch'
    require_eq "$(sha "$module_dir/fuse.ko")" "$FUSE_MODULE_HASH" 'native FUSE module mismatch'
    ensure_prestorage_usd_guard
    write_sitecustomize
    cat > "$RUNTIME_ROOT/load-btrfs.sh" <<EOF
#!/bin/bash
set -Eeuo pipefail
[[ "\$(uname -r)" == "$EXPECTED_KERNEL" ]]
base=$module_dir
[[ "\$(sha256sum "\$base/zstd_compress.ko" | awk '{print \$1}')" == "$ZSTD_MODULE_HASH" ]]
[[ "\$(sha256sum "\$base/btrfs.ko" | awk '{print \$1}')" == "$BTRFS_MODULE_HASH" ]]
[[ "\$(sha256sum "\$base/fuse.ko" | awk '{print \$1}')" == "$FUSE_MODULE_HASH" ]]
grep -qw zstd_compress /proc/modules || insmod "\$base/zstd_compress.ko"
grep -qw btrfs /proc/modules || insmod "\$base/btrfs.ko"
grep -qw fuse /proc/modules || insmod "\$base/fuse.ko"
grep -qw btrfs /proc/filesystems
grep -qw fuse /proc/filesystems
for _ in \$(seq 1 20); do [[ -c /dev/fuse ]] && break; sleep 0.25; done
[[ -c /dev/fuse ]]
EOF
    chmod 0755 "$RUNTIME_ROOT/load-btrfs.sh"
    cat > /etc/systemd/system/unvr-unas-btrfs.service <<EOF
[Unit]
Description=Load exact native storage modules for UNVR Drive
DefaultDependencies=no
Requires=data.mount
After=data.mount systemd-modules-load.service
Before=usd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$RUNTIME_ROOT/load-btrfs.sh

[Install]
WantedBy=multi-user.target
EOF
    install -d -m 755 /etc/systemd/system/usd.service.d
    cat > /etc/systemd/system/usd.service.d/unvr-unas-btrfs.conf <<EOF
[Unit]
Requires=unvr-unas-btrfs.service
After=unvr-unas-btrfs.service

[Service]
Environment=PYTHONPATH=$RUNTIME_ROOT
EOF
    printf '%s\n' '{"max_raid_size":0,"max_volume_size":0,"max_num_volume":1,"prefer_raid":"raid5","prefer_raid_enclosure":{},"filesystem":["btrfs"],"hotspare":false,"hotspare_enclosure":{},"automode":true,"setup":false}' > /etc/ustd/storage.conf
    systemctl daemon-reload
    systemctl enable unvr-unas-btrfs.service >/dev/null
    systemctl restart unvr-unas-btrfs.service
    PYTHONPATH="$RUNTIME_ROOT" python3 - <<'PY'
from ustd.common.utils import check_lvm_enabled, load_hardware_config
from ustd.storage.disk import Disk
from ustd.storage.volume import Volume
assert load_hardware_config()["features"]["FEASSL"] is True
assert check_lvm_enabled() is True
Disk.set_env_support_storage_layout(["raid"])
assert Disk._SUPPORT_STORAGE_LAYOUT == ["raid", "lvm"]
o = Volume.Opts()
o.set_checksum(False)
o.set_cow(False)
assert o.list_mount_opts("btrfs") == ["relatime", "space_cache=v2", "datacow", "datasum"]
PY
    validate_prestorage_usd_guard

    local wsdd_version='2:0.8-1-5+gf36ec348e2fd'
    if [[ "$(pkg_version wsdd)" != "$wsdd_version" || "$(pkg_version wsdd-server)" != "$wsdd_version" ]] ||
       ! pkg_configured wsdd || ! pkg_configured wsdd-server; then
        require_eq "$(sha "$RUNTIME_ROOT/packages/wsdd_0.8.deb")" bf96efcca6bf2993262d095e6c3cf2cbb7e527a4bf21ce747a865f5b3d7668d2 'official UNAS wsdd package mismatch'
        require_eq "$(sha "$RUNTIME_ROOT/packages/wsdd-server_0.8.deb")" 32a3ee30346a49388d652ca7afcea96ef248909ff6afb8f6a04ee6e3158edbdf 'official UNAS wsdd-server package mismatch'
        dpkg -i "$RUNTIME_ROOT/packages/wsdd_0.8.deb" "$RUNTIME_ROOT/packages/wsdd-server_0.8.deb"
    fi
    require_eq "$(pkg_version wsdd)" "$wsdd_version" 'wsdd version mismatch'
    require_eq "$(pkg_version wsdd-server)" "$wsdd_version" 'wsdd-server version mismatch'
    pkg_configured wsdd || die 'wsdd is not fully configured'
    pkg_configured wsdd-server || die 'wsdd-server is not fully configured'
    require_eq "$(sha /usr/bin/wsdd)" a25263168006443c80ce55783af3630c2d75bdb349542f50493cf77d0ed24de2 'wsdd executable hash mismatch'

    local diversion_owner app_group_versions_ready=false base_smb_hash
    diversion_owner=$(dpkg-divert --listpackage /etc/samba/smb.conf 2>/dev/null || true)
    if [[ -z "$diversion_owner" ]]; then
        dpkg-divert --package unifi-drive-config --add --rename \
            --divert /etc/samba/smb.conf.unvr-base /etc/samba/smb.conf
    elif [[ "$diversion_owner" != unifi-drive-config ]]; then
        die "unexpected Samba configuration diversion owner: $diversion_owner"
    fi

    local base_backup
    base_backup=$(cat "$BACKUP_LINK")
    [[ -f "$base_backup/config/smb.conf" && -f /etc/samba/smb.conf.unvr-base ]] \
        || die 'preserved stock Samba configuration is missing'
    require_eq "$(sha /etc/samba/smb.conf.unvr-base)" "$(sha "$base_backup/config/smb.conf")" \
        'diverted Samba configuration differs from the rollback copy'
    base_smb_hash=$(sha /etc/samba/smb.conf.unvr-base)
    if [[ "$(pkg_version unifi-drive)" == 4.3.10 &&
          "$(pkg_version unifi-drive-config)" == 2.23.0-11+ga8a43c45ecd7 &&
          "$(pkg_version unifi-drive-rclone)" == 1.74.4-1+g2b3bd0b0f35e ]]; then
        app_group_versions_ready=true
    fi
    if [[ ! -e /etc/samba/smb.conf ]]; then
        install -o root -g root -m 0644 /etc/samba/smb.conf.unvr-base /etc/samba/smb.conf
    fi
    [[ -f /etc/samba/smb.conf ]] || die 'transitional Samba configuration is missing'
    if [[ "$app_group_versions_ready" == true ]]; then
        if [[ "$(sha /etc/samba/smb.conf)" != "$base_smb_hash" ]] &&
           ! drive_samba_config_semantically_valid /etc/samba/smb.conf; then
            recover_drive_samba_config_5x \
                || die 'installed Drive Samba configuration cannot be validated or recovered'
        fi
    else
        require_eq "$(sha /etc/samba/smb.conf)" "$base_smb_hash" \
            'transitional Samba configuration differs from the validated stock file'
    fi
    if command -v testparm >/dev/null 2>&1; then
        testparm -s --suppress-prompt /etc/samba/smb.conf >/dev/null 2>&1 \
            || die 'transitional Samba configuration is invalid'
    fi

    local immutable_install_rc
    set +e
    install_immutable_dependency_group_5x
    immutable_install_rc=$?
    set -e
    if [[ "$immutable_install_rc" -ne 0 ]]; then
        recover_drive_samba_config_5x \
            || die 'immutable package installation failed and Drive Samba configuration could not be recovered'
    fi
    DEBIAN_FRONTEND=noninteractive timeout 900 dpkg --configure -a
    DEBIAN_FRONTEND=noninteractive timeout 300 dpkg --triggers-only --pending
    if ! drive_samba_config_semantically_valid /etc/samba/smb.conf; then
        recover_drive_samba_config_5x \
            || die 'official Drive Samba configuration cannot be recovered from the pinned package'
        DEBIAN_FRONTEND=noninteractive timeout 900 dpkg --configure -a
        DEBIAN_FRONTEND=noninteractive timeout 300 dpkg --triggers-only --pending
    fi
    validate_immutable_dependency_group_5x
    validate_drive_dependency_group_5x
    require_eq "$(sha /usr/share/unifi-drive/bin/unifi-drive)" b26ed8c0e33bd44a6daf83b2b123513c231665161a9a2b2a70bd852bf5bd4b0a 'official Drive executable hash mismatch'

    install -d -m 755 /etc/systemd/system/unifi-drive.service.d
    cat > /etc/systemd/system/unifi-drive.service.d/unvr-unas-compat.conf <<EOF
[Unit]
Requires=unvr-unas-btrfs.service
After=unvr-unas-btrfs.service
Requires=unvr-unas-identity-restore.service
After=unvr-unas-identity-restore.service

[Service]
Environment=PATH=$RUNTIME_ROOT/drive-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
BindReadOnlyPaths=$RUNTIME_ROOT/drive-bin/ubnt-tools:/sbin/ubnt-tools
BindReadOnlyPaths=$RUNTIME_ROOT/drive-system.info:/proc/ubnthal/system.info
ExecStart=
ExecStart=$RUNTIME_ROOT/unifi-drive-launcher -c /usr/share/unifi-drive/config/config.json
EOF
    systemctl daemon-reload
    validate_drive_service_order_5x
    systemctl enable unifi-drive.service >/dev/null
    systemctl stop usd.service
    systemctl restart uid-agent.service unifi-drive.service
    local deadline=$((SECONDS + 180))
    while (( SECONDS < deadline )); do
        systemctl is-active --quiet unifi-drive.service && break
        sleep 2
    done
    systemctl is-active --quiet unifi-drive.service || die 'Drive did not start on direct 5.1 installation'
    local stable_blank=0
    deadline=$((SECONDS + 120))
    while (( SECONDS < deadline )); do
        if require_prestorage_blank_state >/dev/null 2>&1 && ! systemctl is-active --quiet usd.service && systemctl is-active --quiet unifi-drive.service; then
            stable_blank=$((stable_blank + 1))
            (( stable_blank >= 20 )) && break
        else
            stable_blank=0
        fi
        sleep 3
    done
    (( stable_blank >= 20 )) || die 'slot 1 did not remain blank during the post-install USD stability window'
    mark_done packages
    mark_done compatibility
    log 'exact official Drive 4.3.10 and native storage compatibility installed on clean 5.1 baseline'
}

direct_5x_prestorage_phase() {
    assert_base_5_runtime
    init_state
    phase_done packages || die 'direct 5.1 package phase is incomplete'
    phase_done compatibility || die 'direct 5.1 compatibility phase is incomplete'
    phase_done dedicated-guard || die 'Protect guard phase is incomplete'
    phase_done direct-5x-profile || die 'direct 5.1 profile phase is incomplete'
    phase_done prestorage && { log 'pre-storage UNAS state is already verified'; return; }
    require_prestorage_blank_state
    local storage_state storage_token owner deadline=$((SECONDS + 300)) system_info schema
    IFS='|' read -r storage_state storage_token < "$STATE_ROOT/clean-disk-state"
    case "$storage_state" in
        blank|no-disk) [[ ! -e /dev/md3 ]] || die 'storage was initialized before UNAS onboarding' ;;
        preserve) ;;
        *) die 'pre-storage state is invalid' ;;
    esac
    owner=$(sudo -u postgres psql -X -d ulp-go -A -t -c \
        'SELECT unique_id FROM "user" WHERE deleted_at IS NULL LIMIT 1' 2>/dev/null || true)
    [[ -n "$owner" ]] || die 'current temporary UNVR owner is unavailable'
    while (( SECONDS < deadline )); do
        system_info=$(drive_api GET /api/v1/systems/info "$owner" 2>/dev/null || true)
        schema=$(sudo -u postgres psql -X -d unifi-drive -A -F '|' -t -c 'SELECT version,dirty FROM schema_migrations' 2>/dev/null || true)
        if jq -e '.data.console.model == "UNASPRO" and .data.firmwareVersion == "5.1.33" and .data.version == "4.3.10"' <<<"$system_info" >/dev/null 2>&1 &&
           [[ "$schema" == '123|f' ]]; then
            break
        fi
        sleep 3
    done
    jq -e '.data.console.model == "UNASPRO" and .data.firmwareVersion == "5.1.33" and .data.version == "4.3.10"' <<<"$system_info" >/dev/null \
        || die 'Drive did not expose the final pre-storage UNAS profile'
    require_eq "$schema" '123|f' 'Drive schema migration is incomplete'
    [[ -f "$RUNTIME_ROOT/prestorage-block-usd" ]] || die 'pre-storage USD guard marker is missing'
    ! systemctl is-active --quiet usd.service || die 'usd started before UNAS onboarding'
    for unit in unifi-core unifi-drive uhwd ulp-go udcd nginx unvr-unas-btrfs; do
        systemctl is-active --quiet "$unit" || die "$unit is not active in pre-storage state"
    done
    systemctl is-enabled --quiet unvr-unas-identity-restore.service \
        || die 'identity restore unit is not enabled'
    ! systemctl is-enabled --quiet unvr-unas-drive-restore.service \
        || die 'Drive restore must remain disabled before storage onboarding'
    validate_fuse_runtime
    printf 'physical=UNVR-5.1.33 logical=UNASPRO-5.1.33 storage=%s state=pre-adoption\n' "$storage_state" > "$RUNTIME_ROOT/prestorage-ready"
    rm -f -- "$RUNTIME_ROOT/completed-update" "$RUNTIME_ROOT/pending-update" \
        "$RUNTIME_ROOT/allow-base-update-4.3.10" "$RUNTIME_ROOT/allow-userspace-update-5.1.33" \
        "$RUNTIME_ROOT/allow-base-update-5.1.33" "$RUNTIME_ROOT/restore-drive-version"
    mark_done prestorage
    log "UNAS Pro userspace is ready with storage state $storage_state for official Drive onboarding"
}

direct_5x_validate_prestorage_phase() {
    assert_base_5_runtime
    init_state
    phase_done prestorage || die 'pre-storage UNAS preparation is incomplete'
    validate_stock_unas_apt_policy
    local storage_state storage_token expected_marker owner system_info schema failed deadline
    IFS='|' read -r storage_state storage_token < "$STATE_ROOT/clean-disk-state"
    case "$storage_state" in blank|no-disk|preserve) ;; *) die 'pre-storage state is invalid after reboot' ;; esac
    expected_marker="physical=UNVR-5.1.33 logical=UNASPRO-5.1.33 storage=$storage_state state=pre-adoption"
    require_eq "$(cat "$RUNTIME_ROOT/prestorage-ready" 2>/dev/null || true)" "$expected_marker" 'pre-storage marker mismatch'
    validate_prestorage_disk_resume_state
    case "$storage_state" in
        blank|no-disk) [[ ! -e /dev/md3 ]] || die 'storage was initialized during the validation reboot' ;;
    esac
    deadline=$((SECONDS + 300))
    owner=
    system_info=
    schema=
    while (( SECONDS < deadline )); do
        owner=$(sudo -u postgres psql -X -d ulp-go -A -t -c \
            'SELECT unique_id FROM "user" WHERE deleted_at IS NULL LIMIT 1' 2>/dev/null || true)
        if [[ -n "$owner" ]] && systemctl is-active --quiet unifi-drive.service; then
            system_info=$(drive_api GET /api/v1/systems/info "$owner" 2>/dev/null || true)
            schema=$(sudo -u postgres psql -X -d unifi-drive -A -F '|' -t \
                -c 'SELECT version,dirty FROM schema_migrations' 2>/dev/null || true)
            if jq -e '.data.console.model == "UNASPRO" and .data.firmwareVersion == "5.1.33" and .data.version == "4.3.10"' \
                    <<<"$system_info" >/dev/null 2>&1 && [[ "$schema" == '123|f' ]]; then
                break
            fi
        fi
        sleep 3
    done
    [[ -n "$owner" ]] || die 'temporary UNVR owner is unavailable after reboot'
    jq -e '.data.console.model == "UNASPRO" and .data.firmwareVersion == "5.1.33" and .data.version == "4.3.10"' <<<"$system_info" >/dev/null \
        || die 'UNAS profile did not persist across reboot'
    require_eq "$schema" '123|f' 'Drive schema migration did not finish after reboot'
    [[ -f "$RUNTIME_ROOT/prestorage-block-usd" ]] || die 'pre-storage USD guard did not persist across reboot'
    ! systemctl is-active --quiet usd.service || die 'usd started during the pre-storage reboot'
    for unit in unifi-core unifi-drive uhwd ulp-go udcd nginx unvr-unas-btrfs; do
        systemctl is-active --quiet "$unit" || die "$unit is not active after the pre-storage reboot"
    done
    [[ $(journalctl -b -u unifi-drive.service --no-pager | grep -Eic 'fuse device not found|modprobe fuse' || true) == 0 ]] \
        || die 'Drive started before FUSE was available'
    failed=$(systemctl --failed --no-legend --plain | awk 'NF {count++} END {print count+0}')
    require_eq "$failed" 0 'a systemd unit failed during pre-storage validation'
    validate_fuse_runtime
    mark_done validated-prestorage
    log "pre-storage reboot validation passed; $storage_state storage and UNAS setup identity persisted"
}

arm_update_cmd() {
    die 'OS firmware updates are disabled for the pinned 5.1.33 release'
}

refresh_update_support_cmd() {
    die 'OS update preparation is not supported by this fixed-release converter'
}

disarm_update_cmd() {
    require_root
    rm -f -- "$RUNTIME_ROOT/allow-base-update-4.3.10" \
        "$RUNTIME_ROOT/allow-userspace-update-5.1.32" \
        "$RUNTIME_ROOT/allow-base-update-5.1.33"
    sync
    log 'all guarded update stages are disarmed'
}

dedicated_guard_phase() {
    assert_supported_base
    init_state
    if phase_done dedicated-guard; then
        local guarded_unit guarded_dropin
        [[ ! -e "$RUNTIME_ROOT/protect-enabled" ]] || die 'Protect guard override is unexpectedly enabled'
        for guarded_unit in unifi-protect.service postgresql@14-protect.service postgresql-cluster@14-protect.service postgresql-cluster-14-protect-cleanup.service ms.service msp.service msr.service mst.service ds.service ds-monitor.service msx-monitor.service ai-feature-console.service; do
            guarded_dropin="/etc/systemd/system/$guarded_unit.d/unvr-unas-dedicated.conf"
            [[ -f "$guarded_dropin" ]] || die "Protect guard drop-in is missing: $guarded_unit"
            grep -qx "ConditionPathExists=$RUNTIME_ROOT/protect-enabled" "$guarded_dropin" \
                || die "Protect guard drop-in is invalid: $guarded_unit"
            ! systemctl is-active --quiet "$guarded_unit" \
                || die "guarded Protect/media unit is still active: $guarded_unit"
        done
        log 'dedicated NAS guard already complete and verified'
        return
    fi
    local unit dir
    for unit in unifi-protect.service postgresql@14-protect.service postgresql-cluster@14-protect.service postgresql-cluster-14-protect-cleanup.service ms.service msp.service msr.service mst.service ds.service ds-monitor.service msx-monitor.service ai-feature-console.service; do
        systemctl cat "$unit" >/dev/null 2>&1 || die "expected Protect/media unit missing: $unit"
        dir="/etc/systemd/system/$unit.d"
        install -d -m 755 "$dir"
        cat > "$dir/unvr-unas-dedicated.conf" <<EOF
[Unit]
ConditionPathExists=$RUNTIME_ROOT/protect-enabled
EOF
    done
    rm -f -- "$RUNTIME_ROOT/protect-enabled"
    systemctl daemon-reload
    for unit in unifi-protect.service postgresql@14-protect.service postgresql-cluster@14-protect.service postgresql-cluster-14-protect-cleanup.service ms.service msp.service msr.service mst.service ds.service ds-monitor.service msx-monitor.service ai-feature-console.service; do
        systemctl stop "$unit" >/dev/null 2>&1 || true
        ! systemctl is-active --quiet "$unit" || die "could not stop guarded Protect/media unit: $unit"
    done
    mark_done dedicated-guard
    log 'Protect remains installed but is guarded from dedicated-NAS startup'
}

storage_topology_token() {
    local name device sectors model_hash children inventory=''
    for name in sda sdb sdc sdd; do
        device="/dev/$name"
        if [[ ! -b "$device" ]]; then
            inventory+="$name:absent;"
            continue
        fi
        require_eq "$(cat "/sys/class/block/$name/removable")" 0 "$name unexpectedly resolves to removable media"
        sectors=$(cat "/sys/class/block/$name/size")
        [[ "$sectors" =~ ^[0-9]+$ && "$sectors" -gt 0 ]] || die "$name capacity is invalid"
        model_hash=$(tr -d '\000\n' < "/sys/class/block/$name/device/model" \
            | sed 's/[[:space:]]\+$//' | sha256sum | awk '{print $1}')
        children=$(lsblk -bnrpo NAME,TYPE,SIZE "$device" 2>/dev/null \
            | awk '$2 == "disk" || $2 == "part" {print $1 ":" $2 ":" $3}' \
            | LC_ALL=C sort | paste -sd, -)
        [[ -n "$model_hash" && -n "$children" ]] || die "$name topology could not be read"
        inventory+="$name:$sectors:$model_hash:$children;"
    done
    printf '%s' "$inventory" | sha256sum | awk '{print $1}'
}

no_sata_disks() {
    [[ ! -b /dev/sda && ! -b /dev/sdb && ! -b /dev/sdc && ! -b /dev/sdd ]]
}

print_storage_summary() {
    local name count=0
    for name in sda sdb sdc sdd; do [[ ! -b "/dev/$name" ]] || count=$((count + 1)); done
    printf 'DISK_DISPLAY=%s installed SATA drive(s); existing contents preserved\n' "$count"
}

disk_token() {
    local device=/dev/sda majmin sectors model signature_types partition_count blank_layout=raw
    [[ ! -b /dev/sdb && ! -b /dev/sdc && ! -b /dev/sdd ]] \
        || die 'physical slots 2-4 must be empty during conversion'
    [[ -b "$device" ]] || die 'slot 1 does not resolve to /dev/sda on this exact baseline'
    require_eq "$(cat /sys/class/block/sda/removable)" 0 'slot 1 unexpectedly resolves to removable media'
    [[ $(lsblk -nrpo NAME "$device" | wc -l) -eq 1 ]] || die 'slot 1 disk has a partition table'
    [[ -z $(lsblk -nrpo MOUNTPOINT "$device" | sed '/^$/d') ]] || die 'slot 1 disk or child is mounted'
    [[ -z "$(mdadm --examine --export "$device" 2>/dev/null | grep '^MD_' || true)" ]] \
        || die 'slot 1 disk contains RAID metadata'
    signature_types=$(wipefs -n --noheadings --output TYPE "$device" 2>/dev/null \
        | sed '/^[[:space:]]*$/d;s/^[[:space:]]*//;s/[[:space:]]*$//' \
        | LC_ALL=C sort -u | paste -sd, -)
    if [[ -n "$signature_types" ]]; then
        [[ "$signature_types" == PMBR,gpt ]] || die 'slot 1 disk contains signatures other than an empty GPT'
        partition_count=$(parted -sm "$device" unit s print 2>/dev/null \
            | awk -F: '$1 ~ /^[0-9]+$/ {count++} END {print count+0}')
        [[ "$partition_count" == 0 ]] || die 'slot 1 GPT contains partitions'
        parted -sm "$device" unit s print 2>/dev/null | awk -F: 'NR == 2 && $6 == "gpt" {ok=1} END {exit !ok}' \
            || die 'slot 1 partition-table signatures are not a valid empty GPT'
        blank_layout=empty-gpt
    fi
    majmin=$(cat /sys/class/block/sda/dev)
    sectors=$(cat /sys/class/block/sda/size)
    model=$(tr -d '\000\n' < /sys/class/block/sda/device/model | sed 's/[[:space:]]\+$//')
    [[ "$sectors" =~ ^[0-9]+$ && "$sectors" -gt 200000000 ]] || die 'slot 1 disk capacity is implausible'
    [[ -n "$model" ]] || die 'slot 1 disk model is unavailable'
    printf '%s:%s:%s:%s\n' "$majmin" "$sectors" "$(printf '%s' "$model" | sha256sum | awk '{print $1}')" "$blank_layout"
}

factory_pool_token() {
    local content_check=${1:-full}
    local device=/dev/sda sectors last_sector names layout expected target used md_members db_counts majmin
    [[ -b "$device" ]] || return 1
    [[ ! -b /dev/sdb && ! -b /dev/sdc && ! -b /dev/sdd ]] || return 1
    [[ -z "$(pkg_version unifi-drive)" ]] || return 1
    names=$(lsblk -nrpo NAME,TYPE "$device" \
        | awk '$2 == "disk" || $2 == "part" {print $1}' \
        | LC_ALL=C sort | paste -sd, -)
    [[ "$names" == '/dev/sda,/dev/sda1,/dev/sda2,/dev/sda3,/dev/sda5' ]] || return 1
    sectors=$(cat /sys/class/block/sda/size)
    [[ "$sectors" =~ ^[0-9]+$ && "$sectors" -gt 200000000 ]] || return 1
    last_sector=$((sectors - 34))
    layout=$(parted -sm "$device" unit s print 2>/dev/null \
        | awk -F: '$1 ~ /^[0-9]+$/ {gsub(/s/,"",$2); gsub(/s/,"",$3); print $1 ":" $2 ":" $3}' \
        | paste -sd, -)
    expected="1:2048:1050623,2:2097152:6291455,3:6291456:8388607,5:16777216:${last_sector}"
    [[ "$layout" == "$expected" ]] || return 1
    [[ "$(blkid -s TYPE -o value /dev/sda5 2>/dev/null || true)" == linux_raid_member ]] || return 1
    [[ "$(awk '/^md[0-9]+ :/ {print $1}' /proc/mdstat | paste -sd, -)" == md3 ]] || return 1
    grep -qE '^md3 : active raid1 sda5\[0\]' /proc/mdstat || return 1
    grep -qE '\[2/1\] \[U_\]' /proc/mdstat || return 1
    [[ "$(mdadm --detail /dev/md3 | awk -F: '/Raid Devices/{gsub(/ /,"",$2);print $2}')" == 2 ]] || return 1
    [[ "$(mdadm --detail /dev/md3 | awk -F: '/Active Devices/{gsub(/ /,"",$2);print $2}')" == 1 ]] || return 1
    [[ "$(mdadm --detail /dev/md3 | awk -F: '/Failed Devices/{gsub(/ /,"",$2);print $2}')" == 0 ]] || return 1
    md_members=$(mdadm --detail /dev/md3 | awk '/active sync/ {print $NF}' | paste -sd, -)
    [[ "$md_members" == /dev/sda5 ]] || return 1
    target=$(findmnt -rn -S /dev/md3 -o TARGET,FSTYPE | awk '$2 == "ext4" {print $1; exit}')
    [[ "$target" == /volume/* ]] || return 1
    used=$(df -B1 --output=used "$target" | tail -n1 | tr -d ' ')
    [[ "$used" =~ ^[0-9]+$ && "$used" -le 268435456 ]] || return 1
    [[ "$(find "$target" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort | paste -sd, -)" == '.srv,.volume_runtime_info,lost+found' ]] || return 1
    if [[ "$content_check" == full ]]; then
        db_counts=$(sudo -u postgres psql -X -p 5433 -d unifi-protect -A -F '|' -t -c \
            'SELECT count(*) FILTER (WHERE "isAdopted"),
                    (SELECT count(*) FROM "recordingFiles"),
                    (SELECT count(*) FROM "savedRecordings"),
                    (SELECT count(*) FROM "savedRecordingFiles")
               FROM "cameras";' 2>/dev/null || true)
        [[ "$db_counts" == '0|0|0|0' ]] || return 1
    elif [[ "$content_check" != topology-only ]]; then
        return 1
    fi
    majmin=$(cat /sys/class/block/sda/dev)
    printf '%s\n' "$majmin|$sectors|$layout|md3:raid1:2:1:ext4" | sha256sum | awk '{print $1}'
}

partial_factory_pool_wipe_state() {
    local supplied=$1 marker_state marker_token names target signature_types partition_count
    [[ -f "$STATE_ROOT/clean-disk-state" ]] || return 1
    IFS='|' read -r marker_state marker_token < "$STATE_ROOT/clean-disk-state"
    [[ "$marker_state" == factory-protect-pool && "$marker_token" == "$supplied" ]] || return 1
    names=$(lsblk -nrpo NAME,TYPE /dev/sda \
        | awk '$2 == "disk" || $2 == "part" || $2 == "raid1" {print $1}' \
        | LC_ALL=C sort | paste -sd, -)
    [[ "$names" == '/dev/md3,/dev/sda,/dev/sda5' ]] || return 1
    grep -qE '^md3 : active raid1 sda5\[0\]' /proc/mdstat || return 1
    grep -qE '\[2/1\] \[U_\]' /proc/mdstat || return 1
    [[ "$(mdadm --detail /dev/md3 | awk -F: '/Raid Devices/{gsub(/ /,"",$2);print $2}')" == 2 ]] || return 1
    [[ "$(mdadm --detail /dev/md3 | awk -F: '/Active Devices/{gsub(/ /,"",$2);print $2}')" == 1 ]] || return 1
    [[ "$(mdadm --detail /dev/md3 | awk '/active sync/ {print $NF}')" == /dev/sda5 ]] || return 1
    target=$(findmnt -rn -S /dev/md3 -o TARGET,FSTYPE | awk '$2 == "ext4" {print $1; exit}')
    [[ "$target" == /volume/* ]] || return 1
    partition_count=$(parted -sm /dev/sda unit s print 2>/dev/null \
        | awk -F: '$1 ~ /^[0-9]+$/ {count++} END {print count+0}')
    [[ "$partition_count" == 0 ]] || return 1
    signature_types=$(wipefs -n --noheadings --output TYPE /dev/sda 2>/dev/null \
        | sed '/^[[:space:]]*$/d;s/^[[:space:]]*//;s/[[:space:]]*$//' \
        | LC_ALL=C sort -u | paste -sd, -)
    [[ "$signature_types" == PMBR,gpt ]] || return 1
}

recreated_prestorage_pool_token() {
    local device=/dev/sda sectors last_sector names layout expected md_members majmin marker_state marker_token
    [[ -f "$STATE_ROOT/clean-disk-state" && ! -L "$STATE_ROOT/clean-disk-state" ]] || return 1
    [[ ! -b /dev/sdb && ! -b /dev/sdc && ! -b /dev/sdd ]] || return 1
    IFS='|' read -r marker_state marker_token < "$STATE_ROOT/clean-disk-state"
    [[ "$marker_state" == blank && -n "$marker_token" ]] || return 1
    phase_done direct-5x-profile || return 1
    ! phase_done packages || return 1
    ! phase_done compatibility || return 1
    case "$(pkg_version unifi-drive)" in ''|4.3.10) ;; *) return 1 ;; esac
    names=$(lsblk -nrpo NAME,TYPE "$device" \
        | awk '$2 == "disk" || $2 == "part" {print $1}' \
        | LC_ALL=C sort | paste -sd, -)
    [[ "$names" == '/dev/sda,/dev/sda1,/dev/sda2,/dev/sda3,/dev/sda5' ]] || return 1
    sectors=$(cat /sys/class/block/sda/size)
    [[ "$sectors" =~ ^[0-9]+$ && "$sectors" -gt 200000000 ]] || return 1
    last_sector=$((sectors - 34))
    layout=$(parted -sm "$device" unit s print 2>/dev/null \
        | awk -F: '$1 ~ /^[0-9]+$/ {gsub(/s/,"",$2); gsub(/s/,"",$3); print $1 ":" $2 ":" $3}' \
        | paste -sd, -)
    expected="1:2048:1050623,2:2097152:6291455,3:6291456:8388607,5:16777216:${last_sector}"
    [[ "$layout" == "$expected" ]] || return 1
    [[ "$(awk '/^md[0-9]+ :/ {print $1}' /proc/mdstat | paste -sd, -)" == md3 ]] || return 1
    grep -qE '^md3 : active raid1 sda5\[0\]' /proc/mdstat || return 1
    grep -qE '\[2/1\] \[U_\]' /proc/mdstat || return 1
    [[ "$(mdadm --detail /dev/md3 | awk -F: '/Raid Devices/{gsub(/ /,"",$2);print $2}')" == 2 ]] || return 1
    [[ "$(mdadm --detail /dev/md3 | awk -F: '/Active Devices/{gsub(/ /,"",$2);print $2}')" == 1 ]] || return 1
    [[ "$(mdadm --detail /dev/md3 | awk -F: '/Failed Devices/{gsub(/ /,"",$2);print $2}')" == 0 ]] || return 1
    md_members=$(mdadm --detail /dev/md3 | awk '/active sync/ {print $NF}' | paste -sd, -)
    [[ "$md_members" == /dev/sda5 ]] || return 1
    [[ -z "$(blkid -s TYPE -o value /dev/md3 2>/dev/null || true)" ]] || return 1
    [[ -z "$(findmnt -rn -S /dev/md3 2>/dev/null || true)" ]] || return 1
    majmin=$(cat /sys/class/block/sda/dev)
    printf '%s\n' "$majmin|$sectors|$layout|md3:raid1:2:1:unformatted" | sha256sum | awk '{print $1}'
}

validate_prestorage_usd_guard() {
    local dropin=/etc/systemd/system/usd.service.d/unvr-unas-prestorage.conf
    [[ -f "$RUNTIME_ROOT/prestorage-block-usd" && ! -L "$RUNTIME_ROOT/prestorage-block-usd" ]] \
        || die 'pre-storage USD guard marker is missing or unsafe'
    [[ -f "$dropin" && ! -L "$dropin" ]] || die 'pre-storage USD guard drop-in is missing or unsafe'
    grep -qx "ConditionPathExists=!$RUNTIME_ROOT/prestorage-block-usd" "$dropin" \
        || die 'pre-storage USD guard drop-in is invalid'
    ! systemctl is-active --quiet usd.service || die 'usd is active while pre-storage is guarded'
}

ensure_prestorage_usd_guard() {
    local dropin=/etc/systemd/system/usd.service.d/unvr-unas-prestorage.conf tmp
    install -d -m 755 /etc/systemd/system/usd.service.d
    if [[ -e "$RUNTIME_ROOT/prestorage-block-usd" ]]; then
        [[ -f "$RUNTIME_ROOT/prestorage-block-usd" && ! -L "$RUNTIME_ROOT/prestorage-block-usd" ]] \
            || die 'pre-storage USD guard marker path is unsafe'
    else
        : > "$RUNTIME_ROOT/prestorage-block-usd"
        chmod 600 "$RUNTIME_ROOT/prestorage-block-usd"
    fi
    tmp=$(mktemp /etc/systemd/system/usd.service.d/.unvr-unas-prestorage.XXXXXX)
    printf '[Unit]\nConditionPathExists=!%s/prestorage-block-usd\n' "$RUNTIME_ROOT" > "$tmp"
    chmod 644 "$tmp"
    mv -f "$tmp" "$dropin"
    systemctl daemon-reload
    systemctl stop usd.service
    validate_prestorage_usd_guard
}

require_prestorage_blank_state() {
    local marker_state marker_token current
    [[ -f "$STATE_ROOT/clean-disk-state" && ! -L "$STATE_ROOT/clean-disk-state" ]] \
        || die 'validated clean disk marker is missing or unsafe'
    IFS='|' read -r marker_state marker_token < "$STATE_ROOT/clean-disk-state"
    case "$marker_state" in
        blank) current=$(disk_token) ;;
        no-disk)
            no_sata_disks || die 'a drive was inserted after the no-drive topology was locked'
            current=$(storage_topology_token)
            ;;
        preserve) current=$(storage_topology_token) ;;
        *) die 'storage is not recorded in a safe UNAS onboarding state' ;;
    esac
    require_eq "$current" "$marker_token" 'storage topology changed after validation'
    validate_prestorage_usd_guard
}

validate_prestorage_disk_resume_state() {
    local marker_state marker_token current
    [[ -f "$STATE_ROOT/clean-disk-state" && ! -L "$STATE_ROOT/clean-disk-state" ]] \
        || die 'validated clean disk marker is missing or unsafe'
    IFS='|' read -r marker_state marker_token < "$STATE_ROOT/clean-disk-state"
    case "$marker_state" in
        blank)
            if current=$(disk_token 2>/dev/null); then
                :
            elif current=$(recreated_prestorage_pool_token); then
                validate_prestorage_usd_guard
                return
            else
                die 'blank storage changed and is not the exact recoverable pre-storage pool'
            fi
            ;;
        no-disk)
            no_sata_disks || die 'a drive was inserted during the no-drive conversion'
            current=$(storage_topology_token)
            ;;
        preserve) current=$(storage_topology_token) ;;
        *) die 'recorded pre-storage state is invalid' ;;
    esac
    require_eq "$current" "$marker_token" 'preserved storage topology changed after validation'
    validate_prestorage_usd_guard
}

write_clean_disk_state() {
    local state=$1 token=$2 target="$STATE_ROOT/clean-disk-state" tmp
    case "$state" in blank|factory-protect-pool|no-disk|preserve) ;; *) die 'invalid clean disk state' ;; esac
    [[ -n "$token" ]] || die 'clean disk state token is missing'
    [[ ! -L "$target" ]] || die 'clean disk state marker is unsafe'
    tmp=$(mktemp "$STATE_ROOT/.clean-disk-state.XXXXXX")
    trap 'rm -f -- "$tmp"' RETURN EXIT HUP INT TERM
    printf '%s|%s\n' "$state" "$token" > "$tmp"
    chmod 600 "$tmp"
    sync "$tmp"
    mv -f "$tmp" "$target"
    sync "$target"
    trap - RETURN EXIT HUP INT TERM
}

record_clean_disk_5x_phase() {
    assert_base_5_runtime
    local supplied=${1:-} current state marker="$STATE_ROOT/clean-disk-state" recorded_state recorded_token
    [[ "$supplied" =~ ^[0-9a-f]{64}$ || "$supplied" =~ ^[0-9]+:[0-9]+:[0-9]+:[0-9a-f]{64}:(raw|empty-gpt)$ ]] \
        || die 'validated clean disk token is required'
    if current=$(recreated_prestorage_pool_token); then
        require_eq "$current" "$supplied" 'recreated pre-storage pool changed before it was locked'
        validate_prestorage_usd_guard
        log 'recreated pre-storage pool state recorded and revalidated'
        return
    fi
    if phase_done factory-pool-erased; then
        current=$(disk_token)
        require_eq "$current" "$supplied" 'erased slot-1 disk token differs from the supplied token'
        write_clean_disk_state blank "$current"
        ensure_prestorage_usd_guard
        log 'erased slot-1 disk state recorded and revalidated'
        return
    fi
    if [[ -f "$marker" ]]; then
        IFS='|' read -r recorded_state recorded_token < "$marker"
        require_eq "$recorded_token" "$supplied" 'recorded clean disk token differs from the supplied token'
        case "$recorded_state" in
            factory-protect-pool) current=$(factory_pool_token topology-only) ;;
            blank) current=$(disk_token) ;;
            no-disk)
                no_sata_disks || die 'a drive appeared after the no-drive state was recorded'
                current=$(storage_topology_token)
                ;;
            preserve) current=$(storage_topology_token) ;;
            *) die 'recorded clean disk state is invalid' ;;
        esac
        require_eq "$current" "$recorded_token" 'recorded clean disk topology changed'
        [[ "$recorded_state" == factory-protect-pool ]] || ensure_prestorage_usd_guard
        log 'storage-preservation state already recorded and revalidated'
        return
    fi
    if current=$(factory_pool_token full); then
        state=factory-protect-pool
    elif current=$(disk_token); then
        state=blank
    elif no_sata_disks; then
        state=no-disk
        current=$(storage_topology_token)
    else
        state=preserve
        current=$(storage_topology_token)
    fi
    require_eq "$current" "$supplied" 'storage topology changed before it was recorded'
    init_state
    write_clean_disk_state "$state" "$current"
    [[ "$state" == factory-protect-pool ]] || ensure_prestorage_usd_guard
    log 'validated zero-to-four-drive storage state recorded for guarded resume'
}

recover_legacy_clean_disk_marker_5x_phase() {
    assert_base_5_clean
    local supplied=${1:-} current marker="$STATE_ROOT/clean-disk-state"
    [[ "$supplied" =~ ^[0-9a-f]{64}$ ]] || die 'previously observed clean disk token is required'
    [[ ! -e "$marker" ]] || die 'clean disk marker already exists'
    [[ -f "$STATE_ROOT/version" && "$(cat "$STATE_ROOT/version")" == "$INSTALLER_VERSION" ]] \
        || die 'legacy resume state belongs to another installer version'
    if ! phase_done backup || ! phase_done update-guard || ! phase_done dedicated-guard; then
        die 'legacy resume migration requires completed backup and safety guards'
    fi
    verify_5x_backup
    current=$(factory_pool_token topology-only) \
        || die 'legacy resume disk is not the exact factory-pool topology'
    require_eq "$current" "$supplied" 'legacy resume disk topology differs from the previously validated token'
    write_clean_disk_state factory-protect-pool "$current"
    log 'legacy clean disk validation migrated to guarded resume marker'
}

disk_preflight() {
    assert_base
    if phase_done disk-init; then
        require_eq "$(blkid -s TYPE -o value /dev/md3)" btrfs 'recorded storage pool is no longer Btrfs'
        require_eq "$(findmnt -n -o FSTYPE /volume1)" btrfs 'recorded storage pool is not mounted'
        printf 'DISK_ALREADY_INITIALIZED=1\n'
        return
    fi
    local token sectors size model
    token=$(disk_token)
    sectors=$(cat /sys/class/block/sda/size)
    size=$(numfmt --to=iec-i --suffix=B "$((sectors * 512))")
    model=$(tr -d '\000\n' < /sys/class/block/sda/device/model | sed 's/[[:space:]]\+$//')
    printf 'DISK_TOKEN=%s\n' "$token"
    printf 'DISK_DISPLAY=slot 1 /dev/sda %s %s\n' "$size" "$model"
}

disk_init_phase() {
    assert_base
    init_state
    phase_done disk-init && { log 'disk initialization already complete'; return; }
    local supplied=${1:-}
    [[ -n "$supplied" ]] || die 'disk topology token required'
    require_eq "$(disk_token)" "$supplied" 'disk topology changed after confirmation'
    phase_done compatibility || die 'compatibility phase is incomplete'
    phase_done dedicated-guard || die 'Protect guard phase is incomplete'
    log 'initializing explicitly confirmed blank disk in physical slot 1'
    ustorage disk clean 1
    local deadline=$((SECONDS + 1200))
    while (( SECONDS < deadline )); do
        [[ -b /dev/md0 && -b /dev/md3 ]] && break
        sleep 5
    done
    [[ -b /dev/md0 && -b /dev/md3 ]] || die 'USTD did not create expected md0/md3 arrays'
    local md raid active
    for md in /dev/md0 /dev/md3; do
        raid=$(mdadm --detail "$md" | awk -F: '/Raid Devices/{gsub(/ /,"",$2); print $2}')
        active=$(mdadm --detail "$md" | awk -F: '/Active Devices/{gsub(/ /,"",$2); print $2}')
        if [[ "$raid" == 2 && "$active" == 1 ]]; then
            mdadm --grow "$md" --raid-devices=1 --force
        elif [[ "$raid" != 1 || "$active" != 1 ]]; then
            die "$md topology is outside the validated one-disk transition"
        fi
    done
    deadline=$((SECONDS + 300))
    while (( SECONDS < deadline )); do
        findmnt -n /volume1 >/dev/null 2>&1 && break
        sleep 5
    done
    require_eq "$(blkid -s TYPE -o value /dev/md3)" btrfs 'primary pool is not Btrfs'
    require_eq "$(findmnt -n -o FSTYPE /volume1)" btrfs 'Btrfs pool is not mounted at /volume1'
    ! findmnt -n -o OPTIONS /volume1 | grep -Eq '(^|,)(nodatacow|nodatasum)(,|$)' || die 'unsafe Btrfs mount options detected'
    mark_done disk-init
    log 'single-disk Btrfs pool created with healthy [1/1] RAID metadata'
}

disk_preflight_5x() {
    assert_base_5_runtime
    phase_done packages || die 'direct 5.1 package phase is incomplete'
    phase_done compatibility || die 'direct 5.1 compatibility phase is incomplete'
    phase_done dedicated-guard || die 'Protect guard phase is incomplete'
    if phase_done disk-init; then
        local target
        target=$(findmnt -rn -S /dev/md3 -o TARGET,FSTYPE 2>/dev/null | awk '$2 == "btrfs" {print $1; exit}')
        [[ "$target" == /volume/* ]] || die 'recorded 5.1 pool is not mounted in the multi-volume tree'
        printf 'DISK_ALREADY_INITIALIZED=1\n'
        return
    fi
    local token sectors size model
    token=$(disk_token)
    sectors=$(cat /sys/class/block/sda/size)
    size=$(numfmt --to=iec-i --suffix=B "$((sectors * 512))")
    model=$(tr -d '\000\n' < /sys/class/block/sda/device/model | sed 's/[[:space:]]\+$//')
    printf 'DISK_TOKEN=%s\n' "$token"
    printf 'DISK_DISPLAY=slot 1 /dev/sda %s %s\n' "$size" "$model"
}

disk_preflight_clean_5x() {
    assert_base_5_runtime
    local token deadline stable_blank=0 stable_other=0 previous_other= state=
    if phase_done factory-pool-erased; then
        if token=$(disk_token 2>/dev/null); then
            state=blank
        elif token=$(recreated_prestorage_pool_token); then
            state=recreated-prestorage-pool
        else
            die 'slot 1 changed after the completed factory-pool erase'
        fi
    elif [[ -f "$STATE_ROOT/clean-disk-state" ]] && phase_done dedicated-guard; then
        local recorded_token
        IFS='|' read -r state recorded_token < "$STATE_ROOT/clean-disk-state"
        case "$state" in
            factory-protect-pool) token=$(factory_pool_token topology-only) ;;
            blank)
                if token=$(disk_token 2>/dev/null); then
                    :
                elif token=$(recreated_prestorage_pool_token); then
                    state=recreated-prestorage-pool
                else
                    die 'slot 1 changed after it was recorded as blank'
                fi
                ;;
            no-disk)
                no_sata_disks || die 'a drive appeared after the no-drive state was recorded'
                token=$(storage_topology_token)
                ;;
            preserve) token=$(storage_topology_token) ;;
            *) die 'recorded clean disk state is invalid' ;;
        esac
        if [[ "$state" != recreated-prestorage-pool ]]; then
            require_eq "$token" "$recorded_token" 'slot-1 topology changed after clean-state validation'
        fi
    fi
    if [[ -n "$state" ]]; then
        printf 'DISK_STATE=%s\n' "$state"
        [[ "$state" != factory-protect-pool ]] || printf 'FACTORY_POOL_NEEDS_ERASE=1\n'
        [[ "$state" != recreated-prestorage-pool ]] || printf 'RECREATED_POOL_NEEDS_ERASE=1\n'
        printf 'DISK_TOKEN=%s\n' "$token"
        print_storage_summary
        return
    fi
    deadline=$((SECONDS + 300))
    while (( SECONDS < deadline )); do
        if token=$(factory_pool_token); then
            state=factory-protect-pool
            break
        fi
        if no_sata_disks; then
            state=no-disk
            token=$(storage_topology_token)
            break
        fi
        if token=$(disk_token 2>/dev/null); then
            stable_other=0
            previous_other=
            if phase_done factory-pool-erased; then
                state=blank
                break
            fi
            if systemctl is-active --quiet unifi-protect.service && pg_isready -p 5433 -q; then
                stable_blank=$((stable_blank + 1))
                if (( stable_blank >= 20 )); then
                    state=blank
                    break
                fi
            else
                stable_blank=0
            fi
        else
            token=$(storage_topology_token)
            if systemctl is-active --quiet unifi-protect.service && [[ -b /dev/md3 ]]; then
                stable_other=0
                previous_other=
            elif [[ "$token" == "$previous_other" ]]; then
                stable_other=$((stable_other + 1))
                if (( stable_other >= 20 )); then
                    state=preserve
                    break
                fi
            else
                previous_other=$token
                stable_other=1
            fi
        fi
        sleep 3
    done
    [[ -n "$state" ]] || die 'storage topology did not settle into a preservable state within five minutes'
    printf 'DISK_STATE=%s\n' "$state"
    if [[ "$state" == factory-protect-pool ]]; then
        printf 'FACTORY_POOL_NEEDS_ERASE=1\n'
    fi
    printf 'DISK_TOKEN=%s\n' "$token"
    print_storage_summary
}

lock_clean_disk_5x_phase() {
    local attempt classification token record_output rc
    for attempt in 1 2 3 4 5; do
        set +e
        classification=$(disk_preflight_clean_5x 2>&1)
        rc=$?
        set -e
        if [[ "$rc" -ne 0 ]]; then
            printf '%s\n' "$classification" >&2
            return "$rc"
        fi
        token=$(printf '%s\n' "$classification" | sed -n 's/^DISK_TOKEN=//p')
        [[ "$token" =~ ^[0-9a-f]{64}$ || "$token" =~ ^[0-9]+:[0-9]+:[0-9]+:[0-9a-f]{64}:(raw|empty-gpt)$ ]] \
            || die 'storage classifier did not return a valid topology token'
        set +e
        record_output=$(record_clean_disk_5x_phase "$token" 2>&1)
        rc=$?
        set -e
        if [[ "$rc" -eq 0 ]]; then
            printf '%s\n' "$classification"
            return
        fi
        if grep -qE 'topology changed before it was recorded|changed before it was locked' \
            <<<"$record_output"; then
            sleep 3
            continue
        fi
        printf '%s\n' "$record_output" >&2
        return "$rc"
    done
    die 'storage topology did not remain stable long enough to record safely'
}

erase_factory_pool_5x_phase() {
    assert_base_5_runtime
    init_state
    phase_done backup || die 'backup phase is incomplete before factory-pool cleanup'
    phase_done update-guard || die 'automatic-update guard is incomplete before factory-pool cleanup'
    phase_done dedicated-guard || die 'Protect guard is incomplete before factory-pool cleanup'
    phase_done modules || die 'native modules are not safely staged before factory-pool cleanup'
    if phase_done factory-pool-erased; then
        disk_token >/dev/null
        ensure_prestorage_usd_guard
        log 'factory-created Protect pool was already erased'
        return
    fi
    local supplied=${1:-} current deadline target blank_token marker_state marker_token
    [[ "$supplied" =~ ^[0-9a-f]{64}$ ]] || die 'factory-pool topology token is required'
    if current=$(factory_pool_token topology-only); then
        require_eq "$current" "$supplied" 'factory-created Protect pool changed after confirmation'
    elif partial_factory_pool_wipe_state "$supplied"; then
        log 'resuming from the exact validated partial factory-pool wipe state'
    elif current=$(disk_token 2>/dev/null); then
        IFS='|' read -r marker_state marker_token < "$STATE_ROOT/clean-disk-state"
        [[ "$marker_state" == factory-protect-pool ]] || die 'post-wipe resume marker does not describe the original factory pool'
        require_eq "$marker_token" "$supplied" 'post-wipe resume token differs from the validated factory pool'
        write_clean_disk_state blank "$current"
        ensure_prestorage_usd_guard
        mark_done factory-pool-erased
        log 'official factory-pool wipe was already complete; empty GPT revalidated'
        return
    else
        die 'factory-created Protect pool topology changed before cleanup'
    fi
    log 'erasing the exact empty Protect pool automatically created during temporary UNVR setup'
    systemctl stop unifi-protect.service postgresql@14-protect.service \
        postgresql-cluster@14-protect.service postgresql-cluster-14-protect-cleanup.service \
        ms.service msp.service msr.service mst.service ds.service ds-monitor.service \
        msx-monitor.service ai-feature-console.service >/dev/null 2>&1 || true
    systemctl stop usd.service
    target=$(findmnt -rn -S /dev/md3 -o TARGET,FSTYPE | awk '$2 == "ext4" {print $1; exit}')
    [[ "$target" == /volume/* ]] || die 'factory md3 mount target is invalid before cleanup'
    umount "$target"
    ! findmnt -rn -S /dev/md3 >/dev/null 2>&1 || die 'factory md3 filesystem remained mounted'
    mdadm --stop /dev/md3
    deadline=$((SECONDS + 30))
    while (( SECONDS < deadline )); do [[ ! -e /dev/md3 ]] && break; sleep 1; done
    [[ ! -e /dev/md3 ]] || die 'factory md3 array did not stop cleanly'
    if [[ -L /srv ]]; then
        require_eq "$(readlink /srv)" "$target/.srv" 'stale /srv link does not target the validated factory pool'
        rm -f -- /srv
    fi
    blockdev --rereadpt /dev/sda
    udevadm settle
    timeout 300 /usr/sbin/uscsi_reset_wipe --force
    udevadm settle
    deadline=$((SECONDS + 120))
    while (( SECONDS < deadline )); do
        if [[ ! -e /dev/md3 && $(lsblk -nrpo NAME /dev/sda | wc -l) -eq 1 ]]; then break; fi
        sleep 2
    done
    [[ ! -e /dev/md3 ]] || die 'factory md3 array remained after official slot wipe'
    blank_token=$(disk_token)
    write_clean_disk_state blank "$blank_token"
    ensure_prestorage_usd_guard
    mark_done factory-pool-erased
    log 'factory-created Protect pool removed; slot 1 is blank for UNAS onboarding'
}

erase_recreated_prestorage_pool_5x_phase() {
    assert_base_5_runtime
    init_state
    phase_done direct-5x-profile || die 'UNAS identity profile is not complete'
    ! phase_done packages || die 'Drive package phase is already complete'
    ! phase_done compatibility || die 'storage compatibility phase is already complete'
    local marker_state marker_token
    [[ -f "$STATE_ROOT/clean-disk-state" && ! -L "$STATE_ROOT/clean-disk-state" ]] \
        || die 'original blank-disk marker is missing before recreated-pool cleanup'
    IFS='|' read -r marker_state marker_token < "$STATE_ROOT/clean-disk-state"
    [[ "$marker_state" == blank && -n "$marker_token" ]] \
        || die 'recreated-pool cleanup requires a previously validated blank disk'
    local supplied=${1:-} current deadline blank_token
    [[ "$supplied" =~ ^[0-9a-f]{64}$ ]] || die 'recreated pre-storage pool token is required'
    current=$(recreated_prestorage_pool_token) || die 'recreated pre-storage pool topology changed before cleanup'
    require_eq "$current" "$supplied" 'recreated pre-storage pool changed after validation'
    log 'removing the exact unformatted pool recreated by premature USD startup'
    systemctl stop unifi-drive.service usd.service
    mdadm --stop /dev/md3
    deadline=$((SECONDS + 30))
    while (( SECONDS < deadline )); do [[ ! -e /dev/md3 ]] && break; sleep 1; done
    [[ ! -e /dev/md3 ]] || die 'recreated md3 array did not stop cleanly'
    blockdev --rereadpt /dev/sda
    udevadm settle
    timeout 300 /usr/sbin/uscsi_reset_wipe --force
    udevadm settle
    blank_token=$(disk_token)
    write_clean_disk_state blank "$blank_token"
    log 'recreated unformatted pool removed; slot 1 is blank again'
}

disk_init_5x_phase() {
    assert_base_5_runtime
    init_state
    phase_done disk-init && { log 'direct 5.1 disk initialization already complete'; return; }
    phase_done packages || die 'direct 5.1 package phase is incomplete'
    phase_done compatibility || die 'direct 5.1 compatibility phase is incomplete'
    phase_done dedicated-guard || die 'Protect guard phase is incomplete'
    local supplied=${1:-}
    [[ -n "$supplied" ]] || die 'disk topology token required'
    require_eq "$(disk_token)" "$supplied" 'disk topology changed after confirmation'
    log 'initializing the explicitly confirmed blank slot-1 disk through the native 5.1 storage service'
    ustorage disk clean 1
    local deadline=$((SECONDS + 1200)) md raid active target
    while (( SECONDS < deadline )); do
        [[ -b /dev/md3 ]] && break
        sleep 5
    done
    [[ -b /dev/md3 ]] || die 'USTD did not create the primary md3 array'
    for md in /dev/md3 /dev/md0; do
        [[ -b "$md" ]] || continue
        raid=$(mdadm --detail "$md" | awk -F: '/Raid Devices/{gsub(/ /,"",$2); print $2}')
        active=$(mdadm --detail "$md" | awk -F: '/Active Devices/{gsub(/ /,"",$2); print $2}')
        if [[ "$raid" == 2 && "$active" == 1 ]]; then
            mdadm --grow "$md" --raid-devices=1 --force
        elif [[ "$raid" != 1 || "$active" != 1 ]]; then
            die "$md topology is outside the validated one-disk transition"
        fi
    done
    deadline=$((SECONDS + 600))
    target=
    while (( SECONDS < deadline )); do
        target=$(findmnt -rn -S /dev/md3 -o TARGET,FSTYPE 2>/dev/null | awk '$2 == "btrfs" {print $1; exit}')
        [[ "$target" == /volume/* ]] && break
        sleep 5
    done
    [[ "$target" == /volume/* ]] || die '5.1 Btrfs pool did not mount in the multi-volume tree'
    require_eq "$(blkid -s TYPE -o value /dev/md3)" btrfs 'primary pool is not Btrfs'
    ! findmnt -n -o OPTIONS "$target" | grep -Eq '(^|,)(nodatacow|nodatasum)(,|$)' \
        || die 'unsafe Btrfs mount options detected'
    mark_done disk-init
    log 'single-disk 5.1 Btrfs pool created with healthy [1/1] RAID metadata'
}

drive_api() {
    local method=$1 path=$2 owner=$3 body=${4-}
    if [[ -n "$body" ]]; then
        curl -fsS -X "$method" -H "X-UserId: $owner" -H 'Content-Type: application/json' --data "$body" "http://127.0.0.1:16080$path"
    else
        curl -fsS -X "$method" -H "X-UserId: $owner" "http://127.0.0.1:16080$path"
    fi
}

wait_drive_ready() {
    local owner=$1 deadline=$((SECONDS + 300)) storage state
    while (( SECONDS < deadline )); do
        storage=$(drive_api GET /api/v1/systems/storage "$owner" 2>/dev/null || true)
        state=$(drive_api GET /api/sys/storage/state "$owner" 2>/dev/null || true)
        if jq -e '(.data.status // .status) == "healthy"' <<<"$storage" >/dev/null 2>&1 &&
           jq -e '(.data.ready // .ready) == true' <<<"$state" >/dev/null 2>&1; then return 0; fi
        sleep 3
    done
    return 1
}

validate_fuse_runtime() (
    set -Eeuo pipefail
    grep -qw fuse /proc/modules || die 'FUSE module is not loaded'
    [[ -c /dev/fuse ]] || die 'FUSE device is unavailable'
    [[ -x /usr/sbin/rclone ]] || die 'Drive rclone executable is unavailable'
    local test_root source_dir mount_dir source_hash mounted_hash
    test_root=$(mktemp -d /run/unvr-fuse-validation.XXXXXX)
    source_dir=$test_root/source
    mount_dir=$test_root/mount
    mkdir -m 0700 "$source_dir" "$mount_dir"
    cleanup_fuse_validation() {
        set +e
        mountpoint -q "$mount_dir" && fusermount3 -u "$mount_dir"
        [[ "$test_root" == /run/unvr-fuse-validation.* ]] && rm -rf -- "$test_root"
    }
    trap cleanup_fuse_validation EXIT HUP INT TERM
    printf 'unvr-fuse-source-probe\n' > "$source_dir/source.txt"
    source_hash=$(sha "$source_dir/source.txt")
    /usr/sbin/rclone mount "$source_dir" "$mount_dir" \
        --daemon --vfs-cache-mode writes --log-file "$test_root/rclone.log" --log-level INFO
    for _ in $(seq 1 40); do mountpoint -q "$mount_dir" && break; sleep 0.25; done
    mountpoint -q "$mount_dir" || die 'rclone FUSE mount did not appear'
    require_eq "$(findmnt -rn -o FSTYPE "$mount_dir")" fuse.rclone 'unexpected FUSE mount type'
    require_eq "$(sha "$mount_dir/source.txt")" "$source_hash" 'FUSE read integrity failed'
    printf 'unvr-fuse-mounted-write-probe\n' > "$mount_dir/mounted-write.txt"
    sync "$mount_dir/mounted-write.txt"
    mounted_hash=$(sha "$mount_dir/mounted-write.txt")
    for _ in $(seq 1 40); do [[ -f "$source_dir/mounted-write.txt" ]] && break; sleep 0.25; done
    require_eq "$(sha "$source_dir/mounted-write.txt")" "$mounted_hash" 'FUSE write integrity failed'
    fusermount3 -u "$mount_dir"
    for _ in $(seq 1 40); do ! mountpoint -q "$mount_dir" && break; sleep 0.25; done
    ! mountpoint -q "$mount_dir" || die 'FUSE test mount did not unmount'
)

finalize_drive_patch() {
    local compat="$RUNTIME_ROOT/unifi-drive-legacy-storage-compat"
    python3 - "$compat" <<'PY'
import os, sys
path = sys.argv[1]
with open(path, "rb") as handle:
    data = bytearray(handle.read())
offset = 8530936
temporary = bytes.fromhex("20008052")
original = bytes.fromhex("e0079f9a")
if bytes(data[offset:offset+4]) == temporary:
    data[offset:offset+4] = original
elif bytes(data[offset:offset+4]) != original:
    raise SystemExit("one-time Drive patch source-byte validation failed")
new = path + ".new"
with open(new, "wb") as handle:
    handle.write(data); handle.flush(); os.fsync(handle.fileno())
os.chmod(new, 0o755)
os.replace(new, path)
PY
    require_eq "$(sha "$compat")" "$DRIVE_FINAL_HASH" 'persistent Drive compatibility copy hash mismatch'
}

bootstrap_phase() {
    assert_base
    init_state
    phase_done bootstrap && { log 'Drive bootstrap already complete'; return; }
    require_eq "$(findmnt -n -o FSTYPE /volume1)" btrfs 'Btrfs pool unavailable'
    if ! btrfs qgroup show /volume1 >/dev/null 2>&1; then btrfs quota enable /volume1; fi
    if [[ ! -e /srv/.unifi-drive ]]; then btrfs subvolume create /srv/.unifi-drive; fi
    btrfs subvolume show /srv/.unifi-drive >/dev/null || die '.unifi-drive is not a Btrfs subvolume'
    local drive_uid drive_gid
    drive_uid=$(id -u unifi-drive); drive_gid=$(id -g unifi-drive)
    chown "$drive_uid:$drive_gid" /srv/.unifi-drive
    chmod 0750 /srv/.unifi-drive
    install -d -o "$drive_uid" -g "$drive_gid" -m 0700 /srv/.unifi-drive/homes

    local db_backup="$STATE_ROOT/drive-before-bootstrap.dump"
    if [[ ! -f "$db_backup" ]]; then
        dump_postgres_database unifi-drive "$db_backup"
    fi
    local birth storage_id count
    birth=$(stat -c %w /srv/.unifi-drive/homes)
    storage_id=$(date -d "$birth" +%s%N)
    [[ "$storage_id" =~ ^[0-9]+$ ]] || die 'could not derive validated storage identity'
    count=$(sudo -u postgres psql -X -d unifi-drive -A -t -c 'SELECT count(*) FROM storages')
    if [[ "$count" == 0 ]]; then
        sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d unifi-drive -c "BEGIN; INSERT INTO storages(id,created_at,updated_at) VALUES ('$storage_id',NOW(),NOW()); COMMIT;" >/dev/null
    elif [[ "$count" != 1 ]] || ! sudo -u postgres psql -X -d unifi-drive -A -t -c 'SELECT id FROM storages LIMIT 1' | grep -qx "$storage_id"; then
        die 'Drive storage identity database is in an unknown state'
    fi

    systemctl restart unifi-drive.service
    local deadline=$((SECONDS + 180)) owner profile response
    while (( SECONDS < deadline )); do
        owner=$(sudo -u postgres psql -X -d unifi-drive -A -t -c 'SELECT id FROM users LIMIT 1' 2>/dev/null || true)
        [[ -n "$owner" ]] && curl -fsS -H "X-UserId: $owner" http://127.0.0.1:16080/api/v1/systems/storage >/dev/null 2>&1 && break
        sleep 3
    done
    [[ -n "${owner:-}" ]] || die 'Drive owner record/API did not become ready'
    response=$(drive_api GET /api/v1/systems/storage/personal "$owner")
    if [[ $(jq '.data|length' <<<"$response") == 0 ]]; then
        response=$(drive_api GET '/api/v1/systems/storage/personal?noPersonalDrive=true' "$owner")
        profile=$(jq -er '.data[0].storageProfile.id' <<<"$response")
        drive_api POST /api/v1/systems/storage/personal "$owner" "$(jq -cn --arg id "$profile" '{storageProfile:{id:$id,quota:-1}}')" >/dev/null
    elif [[ $(jq '.data|length' <<<"$response") != 1 ]]; then
        die 'Personal Drive API is in an unknown state'
    fi
    drive_api PUT /api/v1/services/smb/settings "$owner" '{"enable":true}' >/dev/null
    drive_api PUT /api/v1/services/nfs/settings "$owner" '{"enable":true}' >/dev/null
    drive_api PUT "/api/v1/snapshot-settings/personal/$owner" "$owner" '{"maxSnapshots":64,"schedule":{"interval":60,"weekdays":"*","firstRunTime":null,"lastRunTime":null,"enable":false}}' >/dev/null

    systemctl stop unifi-drive.service
    finalize_drive_patch
    systemctl start unifi-drive.service
    wait_drive_ready "$owner" || die 'Drive did not reach healthy/ready after final compatibility patch'
    mark_done bootstrap
    log 'Drive workspace, identity, Personal Drive, SMB, NFS and snapshot defaults provisioned'
}

reboot_phase() {
    assert_supported_base
    init_state
    if phase_done reboot-requested; then
        if [[ -s "$STATE_ROOT/pre-reboot-boot-id" ]] && ! cmp -s "$STATE_ROOT/pre-reboot-boot-id" /proc/sys/kernel/random/boot_id; then
            printf 'REBOOT_ALREADY_COMPLETE=1\n'
            return
        fi
        log 'retrying previously requested reboot that did not complete'
    else
        cat /proc/sys/kernel/random/boot_id > "$STATE_ROOT/pre-reboot-boot-id"
        sync "$STATE_ROOT/pre-reboot-boot-id"
        mark_done reboot-requested
    fi
    sync
    log 'rebooting for persistence validation'
    systemctl reboot
}

handoff_reboot_phase() {
    assert_base_5_runtime
    init_state
    phase_done validated-prestorage || die 'pre-storage reboot validation is incomplete'
    [[ -f "$RUNTIME_ROOT/pending-logical-readoption" ]] \
        || die 'logical UNAS setup handoff is not pending'
    grep -qx 'isSetup: false' /data/unifi-core/config/settings.yaml \
        || die 'console is not in the unmanaged UNAS setup state'
    grep -qx 'name: UNAS Pro' /data/unifi-core/config/settings.yaml \
        || die 'console setup name is not UNAS Pro'
    if phase_done handoff-reboot-requested; then
        if [[ -s "$STATE_ROOT/pre-handoff-boot-id" ]] &&
           ! cmp -s "$STATE_ROOT/pre-handoff-boot-id" /proc/sys/kernel/random/boot_id; then
            printf 'HANDOFF_REBOOT_ALREADY_COMPLETE=1\n'
            return
        fi
        log 'retrying the UNAS discovery handoff reboot'
    else
        cat /proc/sys/kernel/random/boot_id > "$STATE_ROOT/pre-handoff-boot-id"
        sync "$STATE_ROOT/pre-handoff-boot-id"
        mark_done handoff-reboot-requested
    fi
    sync
    log 'rebooting with the unmanaged UNAS Pro hostname and discovery identity'
    systemctl reboot
}

wait_for_unadopted_handoff_ready() {
    local timeout_seconds=${1:-300} deadline system storage unit pending ready_samples=0
    [[ "$timeout_seconds" =~ ^[0-9]+$ && "$timeout_seconds" -gt 0 && "$timeout_seconds" -le 300 ]] \
        || die 'invalid UNAS handoff readiness timeout'
    deadline=$((SECONDS + timeout_seconds))
    # SSH and Core start before Drive. Observe readiness, never restart a
    # service or alter storage to make this validation pass.
    while (( SECONDS < deadline )); do
        [[ -f "$RUNTIME_ROOT/prestorage-block-usd" ]] \
            || die 'pre-storage USD guard is missing after handoff reboot'
        ! systemctl is-active --quiet usd.service \
            || die 'usd started before official UNAS storage onboarding'
        pending=
        for unit in unifi-core unifi-drive uhwd ulp-go udcd nginx unvr-unas-btrfs; do
            ! systemctl is-failed --quiet "$unit" \
                || die "$unit failed during the UNAS handoff reboot"
            systemctl is-active --quiet "$unit" || pending="$pending $unit"
        done
        [[ "$(hostname)" == UNAS-Pro ]] || pending="$pending hostname"
        system=$(curl -ksSf --connect-timeout 2 --max-time 5 https://127.0.0.1/api/system 2>/dev/null || true)
        jq -e '
            .deviceState == "notSetup" and
            .isSetup == false and
            .name == "UNAS Pro" and
            .cloudConnected == false and
            .hardware.shortname == "UNASPRO" and
            .hardware.firmwareVersion == "5.1.33"
        ' <<<"$system" >/dev/null 2>&1 || pending="$pending unmanaged-Core-API"
        storage=$(curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:16080/api/v2/storage 2>/dev/null || true)
        jq -e '(.pools | type) == "array" and (.disks | type) == "array"' \
            <<<"$storage" >/dev/null 2>&1 || pending="$pending Drive-storage-API"
        if [[ -z "$pending" ]]; then
            ready_samples=$((ready_samples + 1))
            (( ready_samples >= 2 )) && return 0
        else
            ready_samples=0
        fi
        sleep 2
    done
    die "UNAS handoff readiness timed out after ${timeout_seconds}s; waiting for:${pending:- stable service and API readiness}"
}

validate_unadopted_handoff_5x() {
    assert_base_5_runtime
    init_state
    phase_done handoff-reboot-requested || die 'UNAS discovery handoff reboot was not requested'
    [[ -s "$STATE_ROOT/pre-handoff-boot-id" ]] || die 'UNAS handoff boot identity is missing'
    ! cmp -s "$STATE_ROOT/pre-handoff-boot-id" /proc/sys/kernel/random/boot_id \
        || die 'UNAS discovery handoff reboot did not complete'
    wait_for_unadopted_handoff_ready
    printf 'UNAS_HANDOFF_OK platform=UNASPRO hostname=UNAS-Pro managed=false\n'
}

cleanup_test_share() {
    local owner=$1 share_name=$2 prior_nfs=$3 action payload
    set +e
    if [[ -n "$prior_nfs" ]]; then drive_api PUT /api/v1/services/nfs/advanced-settings "$owner" "$prior_nfs" >/dev/null 2>&1; fi
    if [[ -n "$share_name" ]] && drive_api GET /api/v1/shared "$owner" \
        | jq -e --arg name "$share_name" '.data[]? | select(.name == $name)' >/dev/null 2>&1; then
        for action in deactivate delete; do
            payload=$(jq -cn --arg action "$action" --arg name "$share_name" \
                '{action:$action,names:[$name]}')
            drive_api POST /api/v1/systems/storage/shared/batch-operation "$owner" "$payload" >/dev/null 2>&1 || true
            sleep 3
        done
    fi
    rm -f -- "$STATE_ROOT/test-share-id"
    set -e
}

validate_phase() {
    assert_base
    init_state
    local compat="$RUNTIME_ROOT/unifi-drive-legacy-storage-compat" owner storage state
    require_eq "$(sha "$compat")" "$DRIVE_FINAL_HASH" 'persistent Drive compatibility hash mismatch'
    systemctl is-active --quiet unvr-unas-btrfs.service || die 'Btrfs loader is not active'
    grep -qw zstd_compress /proc/modules || die 'zstd_compress module is not loaded'
    grep -qw btrfs /proc/modules || die 'Btrfs module is not loaded'
    grep -qw fuse /proc/modules || die 'FUSE module is not loaded'
    [[ -c /dev/fuse ]] || die 'FUSE device is unavailable'
    require_eq "$(findmnt -n -o FSTYPE /volume1)" btrfs 'Btrfs pool did not persist across reboot'
    ! findmnt -n -o OPTIONS /volume1 | grep -Eq '(^|,)(nodatacow|nodatasum)(,|$)' || die 'COW/checksums are disabled after reboot'
    for md in /dev/md0 /dev/md3; do
        [[ $(mdadm --detail "$md" | awk -F: '/Raid Devices/{gsub(/ /,"",$2);print $2}') == 1 ]] || die "$md expected member count is not one"
        [[ $(mdadm --detail "$md" | awk -F: '/Active Devices/{gsub(/ /,"",$2);print $2}') == 1 ]] || die "$md is degraded"
    done
    systemctl is-active --quiet unifi-drive.service || die 'Drive is not active'
    owner=$(sudo -u postgres psql -X -d unifi-drive -A -t -c 'SELECT id FROM users LIMIT 1')
    [[ -n "$owner" ]] || die 'Drive owner record unavailable'
    storage=$(drive_api GET /api/v1/systems/storage "$owner")
    state=$(drive_api GET /api/sys/storage/state "$owner")
    jq -e '((((try .data.status catch null) // .status) == "healthy") or ((.data | type) == "array" and any(.data[]; (.status == "healthy") or (.health == "health") or (.health == "healthy"))))' <<<"$storage" >/dev/null || die 'Drive storage is not healthy'
    jq -e '(.data.ready // .ready) == true' <<<"$state" >/dev/null || die 'Drive framework is not ready'
    [[ $(drive_api GET /api/v1/systems/storage/personal "$owner" | jq '.data|length') == 1 ]] || die 'Personal Drive count is not one'
    systemctl is-active --quiet smbd.service || die 'SMB is inactive'
    systemctl is-active --quiet nfs-server.service || die 'NFS is inactive'
    for unit in unifi-protect.service postgresql@14-protect.service postgresql-cluster@14-protect.service postgresql-cluster-14-protect-cleanup.service ms.service msp.service msr.service mst.service ds.service ds-monitor.service msx-monitor.service ai-feature-console.service; do
        ! systemctl is-active --quiet "$unit" || die "$unit unexpectedly started in dedicated NAS mode"
    done
    systemctl is-enabled --quiet apt-daily.timer && die 'apt-daily.timer is enabled'
    systemctl is-enabled --quiet apt-daily-upgrade.timer && die 'apt-daily-upgrade.timer is enabled'
    local held
    held=$(apt-mark showhold)
    for package in unifi-core ustd ustate-exporter ubntnas unifi-hal ubnt-tools; do
        grep -qx "$package" <<<"$held" || die "$package is not update-held"
    done
    ! grep -qx unifi-drive <<<"$held" || die 'Drive must remain unheld so Core recognizes it as installed'
    ss -lnt | awk '{print $4}' | grep -Eq '(^|:)139$' || die 'SMB port 139 is not listening'
    ss -lnt | awk '{print $4}' | grep -Eq '(^|:)445$' || die 'SMB port 445 is not listening'
    rpcinfo -t 127.0.0.1 nfs 3 >/dev/null || die 'NFSv3 RPC is unavailable'
    smartctl -H /dev/sda | grep -Eq 'PASSED|OK' || die 'slot 1 SMART overall-health test failed'
    require_eq "$(sha /sys/firmware/fdt)" "$EXPECTED_DTB_HASH" 'four-bay device-tree mapping changed'
    ethtool enp0s2 | grep -q 'Speed: 10000Mb/s' || die '10G interface did not negotiate 10,000 Mb/s'
    ethtool enp0s2 | grep -q 'Link detected: yes' || die '10G interface link is down'
    require_eq "$(sha /usr/share/unifi-core/app/service.js)" "$CORE_IDENTITY_HASH" 'Core UNAS identity/health patch is not active'
    systemctl is-enabled --quiet unvr-unas-identity-restore.service || die 'identity restore unit is not enabled'
    systemctl is-enabled --quiet unvr-unas-drive-restore.service || die 'Drive restore unit is not enabled'
    "$RUNTIME_ROOT/guarded-fwupdate" --profile-check >/dev/null

    local existing share_json share_id storage_pool_id prior_response prior_nfs snapshot_id export_path test_mount before_count after_count
    existing=$(drive_api GET /api/v1/shared "$owner")
    ! jq -e '.data[]? | select(.name=="InstallerTest")' <<<"$existing" >/dev/null || die 'InstallerTest already exists but was not created by this validation run'
    storage_pool_id=$(curl -fsS http://127.0.0.1:16080/api/v2/storage \
        | jq -er '(.data.pools // .pools)[0].id')
    share_json=$(drive_api POST /api/v1/shared "$owner" \
        "$(jq -cn --arg pool "$storage_pool_id" '{name:"InstallerTest",quota:-1,members:[],storagePoolId:$pool}')")
    share_id=$(jq -er '.data.id // .id' <<<"$share_json")
    printf '%s\n' "$share_id" > "$STATE_ROOT/test-share-id"
    prior_response=$(drive_api GET /api/v1/services/nfs/advanced-settings "$owner")
    prior_nfs=$(jq -c '{connections:(.data.connections // .connections // [])}' <<<"$prior_response")
    trap 'cleanup_test_share "$owner" InstallerTest "$prior_nfs"' EXIT HUP INT TERM
    drive_api PUT /api/v1/services/nfs/advanced-settings "$owner" "$(jq -cn --arg id "$share_id" '{connections:[{client:"127.0.0.1",sharedDrives:[{id:$id,permission:"rw"}]}]}')" >/dev/null
    drive_api PUT /api/v1/snapshot-settings/shared/InstallerTest "$owner" '{"maxSnapshots":64,"schedule":{"interval":60,"weekdays":"*","firstRunTime":null,"lastRunTime":null,"enable":false}}' >/dev/null
    before_count=$(btrfs subvolume list -s /volume1 | wc -l)
    drive_api POST /api/v1/snapshots/shared/InstallerTest "$owner" '{}' >/dev/null
    local deadline=$((SECONDS + 120)) snapshots
    while (( SECONDS < deadline )); do
        snapshots=$(drive_api GET /api/v1/snapshots/shared/InstallerTest "$owner")
        [[ $(jq '.data|length' <<<"$snapshots") == 1 ]] && break
        sleep 2
    done
    snapshot_id=$(jq -er '.data[0].id' <<<"$snapshots")
    btrfs subvolume list -s /volume1 | grep -q . || die 'Drive snapshot is absent from Btrfs'
    drive_api DELETE "/api/v1/snapshots/shared/InstallerTest/$snapshot_id" "$owner" >/dev/null
    deadline=$((SECONDS + 120))
    while (( SECONDS < deadline )); do
        [[ $(drive_api GET /api/v1/snapshots/shared/InstallerTest "$owner" | jq '.data|length') == 0 ]] && break
        sleep 2
    done
    after_count=$(btrfs subvolume list -s /volume1 | wc -l)
    require_eq "$after_count" "$before_count" 'snapshot deletion did not restore the prior Btrfs snapshot count'

    export_path=/volume1/.srv/.unifi-drive/InstallerTest/.data
    local export_deadline=$((SECONDS + 60))
    while (( SECONDS < export_deadline )); do exportfs -v | grep -Fq "$export_path" && break; sleep 2; done
    exportfs -v | grep -Fq "$export_path" || die 'expected Drive NFS export was not generated'
    test_mount=$(mktemp -d /tmp/unvr-nfs-test.XXXXXX)
    mount -t nfs -o vers=3,nolock,soft,timeo=20,retrans=1 "127.0.0.1:$export_path" "$test_mount"
    dd if=/dev/zero of="$test_mount/.installer-test" bs=4096 count=1 conv=fsync status=none
    require_eq "$(sha "$test_mount/.installer-test")" ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7 'NFS read-back hash mismatch'
    rm -f -- "$test_mount/.installer-test"
    umount "$test_mount"
    rmdir "$test_mount"
    cleanup_test_share "$owner" InstallerTest "$prior_nfs"
    trap - EXIT HUP INT TERM
    ! drive_api GET /api/v1/shared "$owner" | jq -e '.data[]? | select(.name=="InstallerTest")' >/dev/null || die 'temporary validation share was not removed'
    mark_done validated
    log 'post-reboot Drive, Btrfs, FUSE, SMB, NFS, snapshot, SMART, bay-map and 10G checks passed'
}

direct_5x_bootstrap_phase() {
    assert_base_5_runtime
    init_state
    phase_done disk-init || die 'direct 5.1 disk initialization is incomplete'
    phase_done packages || die 'direct 5.1 package phase is incomplete'
    phase_done direct-5x-profile || die 'direct 5.1 profile phase is incomplete'
    phase_done bootstrap && { log 'direct 5.1 bootstrap already complete'; return; }
    local owner deadline=$((SECONDS + 300)) system_info storage schema
    owner=$(sudo -u postgres psql -X -d ulp-go -A -t -c \
        'SELECT unique_id FROM "user" WHERE deleted_at IS NULL LIMIT 1' 2>/dev/null || true)
    [[ -n "$owner" ]] || die 'current ULP owner record is unavailable'
    while (( SECONDS < deadline )); do
        system_info=$(drive_api GET /api/v1/systems/info "$owner" 2>/dev/null || true)
        storage=$(curl -fsS http://127.0.0.1:16080/api/v2/storage 2>/dev/null || true)
        if jq -e '.data.console.model == "UNASPRO" and .data.version == "4.3.10"' <<<"$system_info" >/dev/null 2>&1 &&
           jq -e '(.pools | any(.capacity > 0 and .initializingStatus == "successful" and (.status == "healthy" or .status == "noDataProtectionYet"))) and (.disks | any(.slotId == "1" and .state == "optimal"))' <<<"$storage" >/dev/null 2>&1; then
            break
        fi
        sleep 3
    done
    jq -e '.data.console.model == "UNASPRO" and .data.firmwareVersion == "5.1.33" and .data.version == "4.3.10"' <<<"$system_info" >/dev/null \
        || die 'Drive did not expose the final UNAS profile'
    jq -e '(.pools | any(.capacity > 0 and .initializingStatus == "successful" and (.status == "healthy" or .status == "noDataProtectionYet"))) and (.disks | any(.slotId == "1" and .state == "optimal"))' <<<"$storage" >/dev/null \
        || die 'Drive storage did not become healthy'
    schema=$(sudo -u postgres psql -X -d unifi-drive -A -F '|' -t -c 'SELECT version,dirty FROM schema_migrations' 2>/dev/null || true)
    require_eq "$schema" '123|f' 'Drive schema migration is incomplete'
    drive_api PUT /api/v1/services/smb/settings "$owner" '{"enable":true}' >/dev/null
    drive_api PUT /api/v1/services/nfs/settings "$owner" '{"enable":true}' >/dev/null
    systemctl restart smbd.service nfs-server.service
    for unit in unifi-core unifi-drive usd uhwd ulp-go udcd smbd nfs-server nginx; do
        systemctl is-active --quiet "$unit" || die "$unit is not active after direct 5.1 bootstrap"
    done
    validate_fuse_runtime
    printf '%s\n' 'physical=UNVR-5.1.33 logical=UNASPRO-5.1.33 state=complete' > "$RUNTIME_ROOT/completed-update"
    rm -f -- "$RUNTIME_ROOT/pending-update" "$RUNTIME_ROOT/allow-base-update-4.3.10" \
        "$RUNTIME_ROOT/allow-userspace-update-5.1.33" "$RUNTIME_ROOT/allow-base-update-5.1.33" \
        "$RUNTIME_ROOT/restore-drive-version"
    if ! "$RUNTIME_ROOT/guarded-fwupdate" --profile-check; then
        rm -f -- "$RUNTIME_ROOT/completed-update"
        die 'final guarded profile validation failed'
    fi
    mark_done bootstrap
    log 'direct 5.1 Drive, one-disk storage, SMB, NFS and FUSE bootstrap passed'
}

direct_5x_validate_phase() {
    assert_base_5_runtime
    init_state
    phase_done bootstrap || die 'direct 5.1 bootstrap is incomplete'
    local owner storage iscsi_response failed
    "$RUNTIME_ROOT/guarded-fwupdate" --profile-check >/dev/null
    validate_fuse_runtime
    owner=$(sudo -u postgres psql -X -d ulp-go -A -t -c \
        'SELECT unique_id FROM "user" WHERE deleted_at IS NULL LIMIT 1' 2>/dev/null || true)
    [[ -n "$owner" ]] || die 'current ULP owner record is unavailable after reboot'
    storage=$(curl -fsS http://127.0.0.1:16080/api/v2/storage)
    jq -e '(.pools | any(.capacity > 0 and .initializingStatus == "successful" and (.status == "healthy" or .status == "noDataProtectionYet"))) and (.disks | any(.slotId == "1" and .state == "optimal"))' <<<"$storage" >/dev/null \
        || die 'Drive storage did not persist across reboot'
    for unit in unifi-core unifi-drive usd uhwd ulp-go udcd smbd nfs-server nginx unvr-unas-btrfs; do
        systemctl is-active --quiet "$unit" || die "$unit is not active after reboot"
    done
    [[ $(journalctl -b -u unifi-drive.service --no-pager | grep -Eic 'fuse device not found|modprobe fuse' || true) == 0 ]] \
        || die 'Drive started before FUSE was available'
    failed=$(systemctl --failed --no-legend --plain | awk 'NF {count++} END {print count+0}')
    require_eq "$failed" 0 'a systemd unit failed after reboot'
    ! systemctl is-active --quiet postgresql-cluster@14-protect.service \
        || die 'Protect database setup unexpectedly started'
    ! systemctl is-active --quiet postgresql-cluster-14-protect-cleanup.service \
        || die 'Protect database cleanup unexpectedly started'
    testparm -s >/dev/null 2>&1 || die 'Samba configuration is invalid'
    exportfs -v >/dev/null 2>&1 || die 'NFS export configuration is invalid'
    ss -lnt | awk '{print $4}' | grep -Eq '(^|:)445$' || die 'SMB port 445 is not listening'
    ss -lnt | awk '{print $4}' | grep -Eq '(^|:)2049$' || die 'NFS port 2049 is not listening'
    smartctl -H /dev/sda | grep -Eq 'PASSED|OK' || die 'slot-1 SMART overall health failed'
    ethtool enp0s2 | grep -q 'Speed: 10000Mb/s' || die '10G interface did not negotiate at 10Gb/s'
    ethtool enp0s2 | grep -q 'Link detected: yes' || die '10G interface link is down'
    iscsi_response=$(curl -sS -H "X-UserId: $owner" -H 'X-UserRole: owner' http://127.0.0.1:16080/api/v2/iscsi/luns)
    jq -e '.err.code == "ErrForbidden" and .err.msg == "iSCSI functionality is not supported on this system"' <<<"$iscsi_response" >/dev/null \
        || die 'iSCSI behavior does not match the official UNAS Pro profile'
    mark_done validated
    log 'direct 5.1 reboot validation passed: Drive, storage, FUSE, SMB/NFS, SMART, 10G and UNAS Pro feature parity'
}

status_cmd() {
    require_root
    local volume target_state guard_state
    printf 'Installer state: '
    if [[ -f "$STATE_ROOT/version" ]]; then
        printf 'present (v%s)\n' "$(cat "$STATE_ROOT/version")"
    elif [[ -f "$RUNTIME_ROOT/completed-update" ]]; then
        printf 'migrated final state\n'
    else
        printf 'not installed\n'
    fi
    printf 'Completed phases:'
    if [[ -d "$STATE_ROOT/phases" ]]; then
        find "$STATE_ROOT/phases" -maxdepth 1 -type f -name '*.done' -exec basename {} .done \; | sort | tr '\n' ' '
    elif [[ -f "$RUNTIME_ROOT/completed-update" ]]; then
        printf ' final-migration'
    fi
    printf '\n'
    printf 'Drive package: %s\n' "$(pkg_version unifi-drive)"
    printf 'Drive service: %s\n' "$(systemctl is-active unifi-drive.service 2>/dev/null || true)"
    printf 'System hostname: %s\n' "$(hostname)"
    printf 'Btrfs loader: %s\n' "$(systemctl is-active unvr-unas-btrfs.service 2>/dev/null || true)"
    printf 'FUSE: %s\n' "$(grep -qw fuse /proc/modules && [[ -c /dev/fuse ]] && printf available || printf unavailable)"
    if [[ $(findmnt -rn -o FSTYPE /volume1 2>/dev/null || true) == btrfs ]]; then
        volume='/volume1 btrfs'
    elif findmnt -rn -t btrfs -o TARGET | grep -qE '^/volume/'; then
        volume='multi-volume btrfs'
    else
        volume=unavailable
    fi
    printf 'Volume: %s\n' "$volume"
    case "$(cat /usr/lib/version 2>/dev/null || true)" in
        UNVR4.al324.v4.1.22.47ca036.250414.1648) printf 'Physical base: UNVR 4.1.22\n' ;;
        UNVR4.al324.v5.1.31.5acc35d.260819.1714) printf 'Physical base: UNVR 5.1.31\n' ;;
        UNVR4.al324.v5.1.33.44ce47b.260909.0025) printf 'Physical base: UNVR 5.1.33\n' ;;
        *) printf 'Physical base: unsupported/unknown\n' ;;
    esac
    if [[ -f "$RUNTIME_ROOT/logical-target" ]]; then
        printf 'Logical UNAS target: %s\n' "$(cat "$RUNTIME_ROOT/logical-target")"
    elif [[ -f "$RUNTIME_ROOT/enabled" ]]; then
        printf 'Logical UNAS target: 4.1.22\n'
    fi
    if [[ -f "$RUNTIME_ROOT/allow-base-update-4.3.10" ]]; then
        printf 'Guarded update: stage 1 armed\n'
    elif [[ -f "$RUNTIME_ROOT/allow-userspace-update-5.1.32" ]]; then
        printf 'Guarded update: stage 2 armed\n'
    elif [[ -f "$RUNTIME_ROOT/allow-base-update-5.1.33" ]]; then
        printf 'Guarded update: UNAS 5.1.33 armed\n'
    else
        printf 'Guarded update: disarmed\n'
    fi
    if [[ -f "$RUNTIME_ROOT/prestorage-ready" ]]; then
        printf 'Storage onboarding: pending in UNAS setup\n'
    fi
    target_state=$(awk '/^isSetup:/ {print $2; exit}' /data/unifi-core/config/settings.yaml 2>/dev/null || true)
    printf 'Console setup: %s\n' "${target_state:-unknown}"
    if [[ -f "$RUNTIME_ROOT/prestorage-ready" && ! -f "$RUNTIME_ROOT/completed-update" ]]; then
        printf 'Final profile: awaiting Drive onboarding\n'
    elif [[ -x "$RUNTIME_ROOT/guarded-fwupdate" ]]; then
        guard_state=$($RUNTIME_ROOT/guarded-fwupdate --profile-check 2>/dev/null || true)
        if [[ "$guard_state" == GUARDED_PROFILE_CHECK_OK* ]]; then
            printf 'Final profile: valid\n'
        else
            printf 'Final profile: validation failed\n'
        fi
    fi
}

rollback_cmd() {
    require_root
    require_eq "$(cat /usr/lib/version 2>/dev/null || true)" UNVR4.al324.v4.1.22.47ca036.250414.1648 'automatic installer rollback is only profiled before the 5.x base transition'
    [[ -f "$BACKUP_LINK" ]] || die 'no installer backup is recorded'
    local backup unit state enabled current has_pool=false
    phase_done disk-init && has_pool=true
    backup=$(cat "$BACKUP_LINK")
    (cd "$backup" && sha256sum -c SHA256SUMS >/dev/null) || die 'backup verification failed'
    current=$(sha /usr/share/unifi-core/app/service.js)
    case "$current" in
        "$CORE_IDENTITY_HASH"|"$CORE_PATCHED_HASH"|"$CORE_ORIGINAL_HASH") ;;
        *) die 'refusing rollback over unknown Core bundle' ;;
    esac
    systemctl stop unifi-drive.service >/dev/null 2>&1 || true
    install -o root -g root -m 644 "$backup/config/core-service.js" /usr/share/unifi-core/app/service.js
    install -o root -g root -m 644 "$backup/config/uid-unifi-os-consoles.json" /usr/lib/uid-agent/unifi-os-consoles.json
    install -o root -g root -m 644 "$backup/config/ulp-unifi-os-console.json" /usr/lib/ulp-go/unifi-os-console.json
    [[ ! -f "$backup/config/hostname" ]] || install -o root -g root -m 644 "$backup/config/hostname" /etc/hostname
    [[ ! -f "$backup/config/hosts" ]] || install -o root -g root -m 644 "$backup/config/hosts" /etc/hosts
    [[ ! -f "$backup/config/hostname" ]] || hostname "$(cat /etc/hostname)"
    install -o root -g root -m 644 "$backup/config/portal-index.html" /usr/share/unifi-core/app/node_modules/@ubnt/unifi-portal/dist/local/index.html
    if [[ -f "$backup/config/unifi-assets.tar.gz" ]]; then
        local asset_previous
        asset_previous="/usr/share/unifi-assets.unas-rollback-$(date -u +%Y%m%dT%H%M%SZ)"
        mv /usr/share/unifi-assets "$asset_previous"
        install -d -m 755 /usr/share/unifi-assets
        tar -C /usr/share/unifi-assets -xzf "$backup/config/unifi-assets.tar.gz"
    fi
    rm -f -- "$RUNTIME_ROOT/enabled" "$RUNTIME_ROOT/allow-base-update-4.3.10" \
        "$RUNTIME_ROOT/allow-userspace-update-5.1.32" "$RUNTIME_ROOT/allow-base-update-5.1.33" \
        "$RUNTIME_ROOT/restore-drive-version"
    systemctl disable unvr-unas-identity-restore.service unvr-unas-drive-restore.service >/dev/null 2>&1 || true
    rm -f -- /etc/systemd/system/unvr-unas-identity-restore.service /etc/systemd/system/unvr-unas-drive-restore.service
    if [[ -f /mnt/.rwfs/unvr-unas-firmware/UNVR-5.1.31.bin ]] &&
       [[ "$(sha /mnt/.rwfs/unvr-unas-firmware/UNVR-5.1.31.bin)" == 4656e679a53493c2cfc256bce9e54b6de416abf8acdceef6f6b50517e5780517 ]]; then
        rm -f -- /mnt/.rwfs/unvr-unas-firmware/UNVR-5.1.31.bin
    fi
    if [[ -f "$UPDATE_5_1_33_IMAGE" && ! -L "$UPDATE_5_1_33_IMAGE" ]] &&
       [[ "$(sha "$UPDATE_5_1_33_IMAGE")" == "$UPDATE_5_1_33_IMAGE_SHA256" ]]; then
        rm -f -- "$UPDATE_5_1_33_IMAGE"
    fi
    if [[ "$has_pool" == false ]]; then
        cp -a "$backup/config/storage.conf" /etc/ustd/storage.conf
        for unit in unifi-protect.service postgresql@14-protect.service postgresql-cluster@14-protect.service postgresql-cluster-14-protect-cleanup.service ms.service msp.service msr.service mst.service ds.service ds-monitor.service msx-monitor.service ai-feature-console.service; do
            rm -f -- "/etc/systemd/system/$unit.d/unvr-unas-dedicated.conf"
            rmdir "/etc/systemd/system/$unit.d" 2>/dev/null || true
        done
        rm -f -- /etc/systemd/system/usd.service.d/unvr-unas-btrfs.conf \
            /etc/systemd/system/usd.service.d/unvr-unas-prestorage.conf \
            "$RUNTIME_ROOT/prestorage-block-usd"
        systemctl disable unvr-unas-btrfs.service >/dev/null 2>&1 || true
        rm -f -- /etc/systemd/system/unvr-unas-btrfs.service
    fi
    rm -f -- /etc/systemd/system/unifi-drive.service.d/unvr-unas-compat.conf
    if [[ "$has_pool" == false ]]; then
        rm -f -- /etc/apt/apt.conf.d/99-unvr-unas-no-periodic
        if [[ -f /etc/apt/apt.conf.d/10validuntil && ! -L /etc/apt/apt.conf.d/10validuntil ]] &&
           [[ "$(sha /etc/apt/apt.conf.d/10validuntil)" == "$STOCK_UNAS_VALID_UNTIL_SHA256" ]]; then
            rm -f -- /etc/apt/apt.conf.d/10validuntil
        fi
        while IFS=$'\t' read -r unit state enabled; do
            case "$unit" in
                apt-daily.timer|apt-daily-upgrade.timer)
                    systemctl unmask "$unit" >/dev/null 2>&1 || true
                    [[ "$enabled" == enabled ]] && systemctl enable "$unit" >/dev/null 2>&1 || true
                    [[ "$state" == active ]] && systemctl start "$unit" >/dev/null 2>&1 || true
                    ;;
            esac
        done < "$backup/service-state.tsv"
    fi
    local held_now package
    held_now=$(apt-mark showhold)
    for package in unifi-core ustd ustate-exporter ubntnas unifi-hal ubnt-tools unifi-protect unifi-drive unifi-drive-config unifi-drive-rclone; do
        if [[ "$has_pool" == true ]]; then
            case "$package" in unifi-core|ustd|ustate-exporter|ubntnas|unifi-hal|ubnt-tools) continue ;; esac
        fi
        if grep -qx "$package" <<<"$held_now" && ! grep -qx "$package" "$backup/apt-holds.txt"; then apt-mark unhold "$package" >/dev/null; fi
    done
    DEBIAN_FRONTEND=noninteractive apt-get purge -y unifi-drive unifi-drive-config unifi-drive-rclone >/dev/null 2>&1 || true
    if dpkg-divert --list /etc/samba/smb.conf | grep -q unvr-base; then
        rm -f -- /etc/samba/smb.conf
        dpkg-divert --package unifi-drive-config --rename --remove /etc/samba/smb.conf
    fi
    systemctl daemon-reload
    systemctl restart uid-agent.service ulp-go.service unifi-core.service
    if [[ "$has_pool" == false ]]; then
        systemctl restart usd.service
        while IFS=$'\t' read -r unit state enabled; do
            case "$unit" in
                unifi-protect.service|postgresql@14-protect.service|postgresql-cluster@14-protect.service|postgresql-cluster-14-protect-cleanup.service|ms.service|msp.service|msr.service|mst.service)
                    [[ "$state" == active ]] && systemctl start "$unit" >/dev/null 2>&1 || true
                    ;;
            esac
        done < "$backup/service-state.tsv"
    else
        log 'Btrfs loader, USTD shim and Protect guard retained to preserve the existing Drive pool safely'
    fi
    printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_ROOT/ROLLED_BACK"
    log 'software rollback complete; the SATA pool and its data were intentionally preserved'
    log 'reboot is recommended after copying any needed Drive data elsewhere'
}

acquire_phase_lock() {
    command -v flock >/dev/null 2>&1 || die 'required phase-lock utility is unavailable'
    install -d -m 755 /run/lock
    exec 9> /run/lock/unvr-unas-installer.lock
    flock -n 9 || die 'another UNVR-to-UNAS installer phase is already running'
}

acquire_phase_lock
case "${1:-}" in
    detect-baseline) detect_baseline_cmd ;;
    factory-reset-preflight) factory_reset_preflight_cmd ;;
    factory-network-association) factory_network_association_cmd "${2:-}" ;;
    factory-cloud-unregister) factory_cloud_unregister_cmd ;;
    factory-reset-wipe) factory_reset_wipe_cmd ;;
    normalization-preflight) normalization_source_preflight ;;
    normalization-image-stage) stage_normalization_image ;;
    normalization-image-check) validate_normalization_image ;;
    normalize-to-5x) normalize_to_5x ;;
    preflight) preflight ;;
    preflight-5x) preflight_5x ;;
    backup) backup_phase ;;
    backup-5x) backup_5x_phase ;;
    update-guard) auto_update_guard_phase ;;
    core-patch) core_patch_phase ;;
    packages) packages_phase ;;
    modules) build_modules_phase "${2:-}" ;;
    compatibility) compatibility_phase ;;
    update-integration) die 'legacy OS migration is not supported by this fixed-release converter' ;;
    direct-5x-profile) direct_5x_profile_phase "${2:-}" ;;
    direct-5x-packages) direct_5x_packages_phase ;;
    prestorage-5x) direct_5x_prestorage_phase ;;
    validate-prestorage-5x) direct_5x_validate_prestorage_phase ;;
    refresh-update-support) refresh_update_support_cmd "${2:-}" "${3:-}" "${4:-}" "${5:-}" ;;
    arm-update) arm_update_cmd "${2:-}" ;;
    disarm-update) disarm_update_cmd ;;
    dedicated-guard) dedicated_guard_phase ;;
    disk-preflight) disk_preflight ;;
    disk-preflight-5x) disk_preflight_5x ;;
    disk-preflight-clean-5x) disk_preflight_clean_5x ;;
    lock-clean-disk-5x) lock_clean_disk_5x_phase ;;
    record-clean-disk-5x) record_clean_disk_5x_phase "${2:-}" ;;
    recover-legacy-clean-disk-marker-5x) recover_legacy_clean_disk_marker_5x_phase "${2:-}" ;;
    erase-factory-pool-5x) erase_factory_pool_5x_phase "${2:-}" ;;
    erase-recreated-pool-5x) erase_recreated_prestorage_pool_5x_phase "${2:-}" ;;
    disk-init) disk_init_phase "${2:-}" ;;
    disk-init-5x) disk_init_5x_phase "${2:-}" ;;
    bootstrap) bootstrap_phase ;;
    bootstrap-5x) direct_5x_bootstrap_phase ;;
    reboot) reboot_phase ;;
    handoff-reboot) handoff_reboot_phase ;;
    validate-unadopted-handoff-5x) validate_unadopted_handoff_5x ;;
    validate) validate_phase ;;
    validate-5x) direct_5x_validate_phase ;;
    logical-unadopt) "$RUNTIME_ROOT/logical-unadopt" enter ;;
    status) status_cmd ;;
    rollback) rollback_cmd ;;
    *) die 'unknown remote phase' ;;
esac
