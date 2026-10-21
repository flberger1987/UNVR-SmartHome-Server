#!/bin/bash
# Reconstruct the exact wsdd/wsdd-server package payloads from official UNAS
# 5.1.33 firmware. No Ubiquiti binary is embedded in this repository.

set -Eeuo pipefail
export LC_ALL=C
export COPYFILE_DISABLE=1
export ZERO_AR_DATE=1
# touch -t interprets 202001010000 in local time; the pinned package hashes were
# produced at UTC-5, so fix the zone to build identically everywhere.
export TZ=Etc/GMT+5
umask 077

readonly IMAGE_SIZE=693903010
readonly IMAGE_SHA=0d711a42b68649bf2a9e129123211e59896d8b29860d85c8c43b4e98d2c59d66
readonly ROOTFS_OFFSET=26152274
readonly VERSION='2:0.8-1-5+gf36ec348e2fd'

image=${1:-}
output=${2:-}
output_created=false
build_complete=false

die() { printf '[wsdd-builder] ERROR: %s\n' "$*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | awk '{print $1}'; }

cleanup() {
    local rc=$?
    set +e
    if [[ "$build_complete" != true && "$output_created" == true && -n "$output" && -d "$output" && ! -L "$output" ]]; then
        rm -rf -- "$output"
    fi
    exit "$rc"
}
trap cleanup EXIT HUP INT TERM

[[ $(uname -s) == Darwin ]] || die 'this builder currently supports macOS only'
[[ -f "$image" && -n "$output" ]] || die 'usage: build_wsdd_5x_debs_macos.sh UNAS_5.1.33.bin OUTPUT_DIR'
[[ ! -e "$output" ]] || die 'output directory already exists'
[[ $(stat -f '%z' "$image") == "$IMAGE_SIZE" ]] || die 'UNAS 5.1.33 image size mismatch'
[[ $(sha "$image") == "$IMAGE_SHA" ]] || die 'UNAS 5.1.33 image SHA-256 mismatch'
for tool in ar awk gzip shasum tar unsquashfs; do
    command -v "$tool" >/dev/null 2>&1 || die "required command not found: $tool"
done

mkdir -m 700 "$output"
output_created=true
output=$(CDPATH='' cd -- "$output" && pwd)
available_kib=$(df -Pk "$output" | awk 'NR == 2 {print $4}')
[[ "$available_kib" =~ ^[0-9]+$ && "$available_kib" -ge 1048576 ]] \
    || die 'at least 1 GiB of free local space is required to reconstruct wsdd packages'
rootfs="$output/rootfs"
(
    umask 022
    unsquashfs -no-progress -no-xattrs -d "$rootfs" -o "$ROOTFS_OFFSET" "$image" \
        etc/default/wsdd \
        lib/systemd/system/wsdd-server.service \
        usr/bin/wsdd \
        usr/share/doc/wsdd \
        usr/share/doc/wsdd-server \
        usr/share/lintian/overrides/wsdd \
        usr/share/man/man1/wsdd.1.gz \
        var/lib/dpkg/status \
        var/lib/dpkg/info/wsdd.list \
        var/lib/dpkg/info/wsdd.md5sums \
        var/lib/dpkg/info/wsdd-server.conffiles \
        var/lib/dpkg/info/wsdd-server.list \
        var/lib/dpkg/info/wsdd-server.md5sums \
        var/lib/dpkg/info/wsdd-server.postinst \
        var/lib/dpkg/info/wsdd-server.prerm \
        var/lib/dpkg/info/wsdd-server.postrm \
        >/dev/null
)

extract_control() {
    local package=$1 destination=$2
    awk -v package="$package" '
        BEGIN { RS=""; FS="\n" }
        $0 ~ ("^Package: " package "$") || $0 ~ ("^Package: " package "\\n") {
            skip=0
            for (i=1; i<=NF; i++) {
                if ($i ~ /^Status:/) continue
                if ($i ~ /^Conffiles:/) { skip=1; continue }
                if (skip && $i ~ /^ /) continue
                skip=0
                print $i
            }
            found=1
        }
        END { if (!found) exit 1 }
    ' "$rootfs/var/lib/dpkg/status" > "$destination"
}

copy_package_data() {
    local package=$1 package_root=$2 entry relative source mode
    while IFS= read -r entry; do
        [[ "$entry" == /. ]] && continue
        [[ "$entry" == /* && "$entry" != *'/../'* && "$entry" != */.. && "$entry" != *$'\n'* ]] \
            || die "unsafe path in $package list: $entry"
        relative=${entry#/}
        source="$rootfs/$relative"
        if [[ ! -e "$source" && ! -L "$source" ]]; then
            case "$entry" in
                /usr/share/doc/*|/usr/share/man/*|/usr/share/lintian/*)
                    # UniFi firmware deliberately prunes non-runtime package
                    # documentation while retaining the original dpkg lists.
                    continue
                    ;;
                *)
                    die "missing official $package runtime payload: $entry"
                    ;;
            esac
        fi
        if [[ -d "$source" ]]; then
            mode=$(stat -f '%Lp' "$source")
            mkdir -p "$package_root/$relative"
            chmod "$mode" "$package_root/$relative"
        else
            mkdir -p "$(dirname "$package_root/$relative")"
            cp -pP "$source" "$package_root/$relative"
            mode=$(stat -f '%Lp' "$source")
            chmod "$mode" "$package_root/$relative"
        fi
    done < "$rootfs/var/lib/dpkg/info/$package.list"
}

build_package() {
    local package=$1 root control
    root="$output/$package-root"
    control="$output/$package-control"
    local work="$output/$package-build" data_tar control_tar binary
    local deb="$output/${package}_${VERSION/:/%3a}_all.deb"
    data_tar="$work/data.tar.gz"
    control_tar="$work/control.tar.gz"
    binary="$work/debian-binary"
    mkdir -p "$root" "$control" "$work"
    copy_package_data "$package" "$root"
    extract_control "$package" "$control/control"
    cp -p "$rootfs/var/lib/dpkg/info/$package.md5sums" "$control/md5sums"
    if [[ "$package" == wsdd-server ]]; then
        cp -p "$rootfs/var/lib/dpkg/info/$package.conffiles" "$control/conffiles"
        cp -p "$rootfs/var/lib/dpkg/info/$package.postinst" "$control/postinst"
        cp -p "$rootfs/var/lib/dpkg/info/$package.prerm" "$control/prerm"
        cp -p "$rootfs/var/lib/dpkg/info/$package.postrm" "$control/postrm"
        chmod 755 "$control/postinst" "$control/prerm" "$control/postrm"
    fi
    chmod 644 "$control/control" "$control/md5sums"
    [[ ! -f "$control/conffiles" ]] || chmod 644 "$control/conffiles"
    find "$root" "$control" -exec touch -h -t 202001010000 {} +
    printf '2.0\n' > "$binary"
    touch -t 202001010000 "$binary"
    (
        umask 022
        cd "$control"
        find . -print | LC_ALL=C sort \
            | tar --no-recursion --format=ustar --uid 0 --gid 0 --uname root --gname root -cf - -T - \
            | gzip -n > "$control_tar"
    )
    (
        umask 022
        cd "$root"
        find . -print | LC_ALL=C sort \
            | tar --no-recursion --format=ustar --uid 0 --gid 0 --uname root --gname root -cf - -T - \
            | gzip -n > "$data_tar"
    )
    (
        cd "$work"
        # -S: newer Xcode command line tools add a __.SYMDEF symbol table by
        # default, which is not valid in a Debian package.
        ar -rcS "$deb" "$(basename "$binary")" "$(basename "$control_tar")" "$(basename "$data_tar")"
    )
    [[ $(ar -t "$deb" | tr '\n' ' ') == 'debian-binary control.tar.gz data.tar.gz ' ]] \
        || die "$package archive is malformed"
    printf '%s\t%s\n' "$deb" "$(sha "$deb")"
}

build_package wsdd
build_package wsdd-server
build_complete=true
