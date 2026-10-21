#!/bin/bash
# Build a temporary, hash-manifested compatibility payload from official images.
# No extracted Ubiquiti binary is stored in this repository by this script.

set -Eeuo pipefail
export LC_ALL=C
export COPYFILE_DISABLE=1
# touch -t interprets 202001010000 in local time; the pinned archive hashes were
# produced at UTC-5, so fix the zone to build identically everywhere.
export TZ=Etc/GMT+5
umask 077

readonly UNVR5_URL=https://fw-download.ubnt.com/data/unifi-nvr/976a-UNVR-5.1.33-84c520f3-fb97-41e0-be2b-b0f89c46c7b8.bin
readonly UNVR5_SIZE=787559347
readonly UNVR5_SHA=b170e97f9b7a703947380aed1108221e70ab18074b986906aca9df10891ca1e0
readonly UNVR5_OFFSET=15241827
readonly UNAS5_URL=https://fw-download.ubnt.com/data/unifi-drive/7a07-UNASPRO-5.1.33-10b23dea-e891-4699-bd66-3ecff7f954db.bin
readonly UNAS5_SIZE=693903010
readonly UNAS5_SHA=0d711a42b68649bf2a9e129123211e59896d8b29860d85c8c43b4e98d2c59d66
readonly UNAS5_OFFSET=26152274
readonly KBUILD_CLOSURE_SHA=fb99e5bfe01f99d9f40f613e7610ec34c77a1c67c0264f74b26cc455487471f8

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
output_dir=
artifact_cache=
unvr5=
unas5=
build_complete=false
output_created=false

die() { printf '[profile-builder] ERROR: %s\n' "$*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | awk '{print $1}'; }

download_exact() {
    local url=$1 destination=$2 expected_size=$3 expected_sha=$4 label=$5
    local attempt actual_size=0 curl_rc
    [[ ! -e "$destination" || ( -f "$destination" && ! -L "$destination" ) ]] \
        || die "$label download path is unsafe"
    if [[ -n "$artifact_cache" && "$destination" == "$output_dir/"* ]]; then
        local relative=${destination#"$output_dir"/} cached
        relative=${relative%.part}
        cached="$artifact_cache/$relative"
        if [[ -f "$cached" && ! -L "$cached" && $(stat -f '%z' "$cached") == "$expected_size" &&
              $(sha "$cached") == "$expected_sha" ]]; then
            cp -p "$cached" "$destination"
            return 0
        fi
    fi
    for attempt in $(seq 1 12); do
        if [[ -f "$destination" ]]; then
            actual_size=$(stat -f '%z' "$destination")
            if [[ "$actual_size" -eq "$expected_size" && "$(sha "$destination")" == "$expected_sha" ]]; then
                return 0
            fi
            if [[ "$actual_size" -ge "$expected_size" ]]; then
                rm -f -- "$destination"
                actual_size=0
            fi
        fi
        curl_rc=0
        curl -fL --silent --show-error --proto '=https' --tlsv1.2 --http1.1 \
            --connect-timeout 20 --retry 2 --retry-delay 1 --retry-connrefused --retry-all-errors \
            --speed-limit 16384 --speed-time 120 --continue-at - \
            "$url" -o "$destination" || curl_rc=$?
        if [[ -f "$destination" ]]; then
            actual_size=$(stat -f '%z' "$destination")
            if [[ "$actual_size" -eq "$expected_size" && "$(sha "$destination")" == "$expected_sha" ]]; then
                return 0
            fi
        fi
        case "$curl_rc" in
            33|36) rm -f -- "$destination"; actual_size=0 ;;
        esac
        printf '[profile-builder] retrying %s transfer (%s/12, %s/%s bytes)\n' \
            "$label" "$attempt" "$actual_size" "$expected_size" >&2
        sleep 2
    done
    die "$label download did not reach its pinned size and SHA-256"
}

cleanup() {
    local rc=$?
    set +e
    if [[ "$build_complete" != true && "$output_created" == true && -n "$output_dir" && -d "$output_dir" && ! -L "$output_dir" ]]; then
        rm -rf -- "$output_dir"
    fi
    exit "$rc"
}
trap cleanup EXIT HUP INT TERM

usage() {
    cat <<'EOF'
Usage: build_update_profiles_macos.sh OUTPUT_DIR [options]

Options:
  --unvr-5 FILE   Exact official UNVR 5.1.33 image
  --unas-5 FILE   Exact official UNAS Pro 5.1.33 image
  --artifact-cache DIR  Reuse verified downloads from a previous profile build

Firmware files are not required in the repository. Missing images are
downloaded from Ubiquiti's official firmware host into OUTPUT_DIR and accepted
only after exact size and SHA-256 validation. An optional exact local cache is
reused when present. OUTPUT_DIR must not already exist and should be treated as
private temporary storage.
EOF
}

[[ $(uname -s) == Darwin ]] || die 'this profile builder currently supports macOS only'
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[[ $# -ge 1 ]] || { usage >&2; exit 2; }
output_dir=$1
shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --unvr-5) [[ $# -ge 2 ]] || die '--unvr-5 requires a file'; unvr5=$2; shift 2 ;;
        --unas-5) [[ $# -ge 2 ]] || die '--unas-5 requires a file'; unas5=$2; shift 2 ;;
        --artifact-cache) [[ $# -ge 2 ]] || die '--artifact-cache requires a directory'; artifact_cache=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done
[[ -z "$artifact_cache" || ( -d "$artifact_cache" && ! -L "$artifact_cache" ) ]] \
    || die 'artifact cache directory is missing or unsafe'
[[ ! -e "$output_dir" ]] || die 'output directory already exists'
mkdir -m 700 "$output_dir"
output_created=true
available_kib=$(df -Pk "$output_dir" | awk 'NR == 2 {print $4}')
[[ "$available_kib" =~ ^[0-9]+$ && "$available_kib" -ge 6291456 ]] \
    || die 'at least 6 GiB of free local space is required to build the compatibility payload'

for tool in curl unsquashfs node python3 tar gzip shasum ar xz; do
    command -v "$tool" >/dev/null 2>&1 || die "required command not found: $tool"
done

resolve_image() {
    local supplied=$1 cached=$2 url=$3 size=$4 expected=$5 destination=$6 label=$7 selected part
    if [[ -n "$supplied" ]]; then
        selected=$supplied
    elif [[ -f "$cached" && $(stat -f '%z' "$cached") == "$size" && $(sha "$cached") == "$expected" ]]; then
        selected=$cached
    else
        part="$destination.part"
        rm -f -- "$part"
        printf '[profile-builder] downloading %s from Ubiquiti\n' "$label" >&2
        download_exact "$url" "$part" "$size" "$expected" "$label"
        mv -f "$part" "$destination"
        selected=$destination
    fi
    [[ -f "$selected" ]] || die "$label image is missing"
    [[ $(stat -f '%z' "$selected") == "$size" ]] || die "$label size mismatch"
    [[ $(sha "$selected") == "$expected" ]] || die "$label SHA-256 mismatch"
    printf '%s\n' "$selected"
}

unvr5=$(resolve_image "$unvr5" "$project_root/analysis/firmware/UNVR-5.1.33.bin" "$UNVR5_URL" "$UNVR5_SIZE" "$UNVR5_SHA" "$output_dir/UNVR-5.1.33.bin" 'UNVR 5.1.33')
unas5=$(resolve_image "$unas5" "$project_root/analysis/firmware/UNASPRO-5.1.33.bin" "$UNAS5_URL" "$UNAS5_SIZE" "$UNAS5_SHA" "$output_dir/UNASPRO-5.1.33.bin" 'UNAS Pro 5.1.33')

extract_root="$output_dir/extracted"
payload="$output_dir/payload"
mkdir -p "$extract_root/unvr5" "$extract_root/unas5"
mkdir -p "$payload/profiles/5.1.33" "$payload/tools" "$payload/packages"

unsquashfs -no-progress -no-xattrs -d "$extract_root/unvr5" -o "$UNVR5_OFFSET" "$unvr5" \
    usr/share/unifi-core/app/service.js \
    usr/lib/uid-agent/unifi-os-consoles.json \
    usr/lib/ulp-go/unifi-os-console.json \
    usr/share/unifi-core/app/node_modules/@ubnt/unifi-portal/dist/local \
    >/dev/null
unsquashfs -no-progress -no-xattrs -d "$extract_root/unas5" -o "$UNAS5_OFFSET" "$unas5" \
    usr/share/unifi-assets-bundle/UNASPRO \
    usr/share/unifi-core/app/node_modules/@ubnt/uhd-setup/dist/index.html \
    usr/share/unifi-core/app/node_modules/@ubnt/unifi-portal/dist/local/index.html \
    >/dev/null

python3 "$script_dir/build_5x_identity_overlays.py" \
    "$extract_root/unvr5/usr/lib/uid-agent/unifi-os-consoles.json" \
    "$extract_root/unvr5/usr/lib/ulp-go/unifi-os-console.json" \
    "$payload/profiles/5.1.33/uid-unifi-os-consoles.json" \
    "$payload/profiles/5.1.33/ulp-unifi-os-console.json" \
    >/dev/null
node "$script_dir/build_core_5x_unaspro_patch.js" \
    "$extract_root/unvr5/usr/share/unifi-core/app/service.js" \
    "$payload/profiles/5.1.33/core-service.js" 5.1.33 \
    >/dev/null
node "$script_dir/verify_storage_ui_contract.js" \
    "$payload/profiles/5.1.33/core-service.js" \
    "$extract_root/unvr5/usr/share/unifi-core/app/node_modules/@ubnt/unifi-portal/dist/local" \
    >/dev/null

make_asset_archive() {
    local source=$1 destination=$2
    find "$source" -type d -exec chmod 0755 {} +
    find "$source" -type f -exec chmod 0644 {} +
    find "$source" -exec touch -h -t 202001010000 {} +
    (
        cd "$source"
        find . -print | LC_ALL=C sort \
            | tar --no-recursion --format=ustar --uid 0 --gid 0 --uname root --gname root -cf - -T - \
            | gzip -n > "$destination"
    )
}
make_asset_archive "$extract_root/unas5/usr/share/unifi-assets-bundle/UNASPRO" "$payload/profiles/5.1.33/unifi-assets.tar.gz"
cp -p "$extract_root/unas5/usr/share/unifi-core/app/node_modules/@ubnt/uhd-setup/dist/index.html" \
    "$payload/profiles/5.1.33/uhd-setup-index.template.html"
cp -p "$extract_root/unas5/usr/share/unifi-core/app/node_modules/@ubnt/unifi-portal/dist/local/index.html" \
    "$payload/profiles/5.1.33/portal-index.template.html"

wsdd_build="$output_dir/wsdd-5x"
"$script_dir/build_wsdd_5x_debs_macos.sh" "$unas5" "$wsdd_build" >/dev/null
cp -p "$wsdd_build/wsdd_2%3a0.8-1-5+gf36ec348e2fd_all.deb" "$payload/packages/wsdd_0.8.deb"
cp -p "$wsdd_build/wsdd-server_2%3a0.8-1-5+gf36ec348e2fd_all.deb" "$payload/packages/wsdd-server_0.8.deb"

fetch_verified_deb() {
    local filename=$1 url=$2 expected_size=$3 expected_sha=$4
    local expected_package=$5 expected_version=$6 expected_arch=$7 label=$8
    local package_root=${9:-"$payload/packages"} target part
    target="$package_root/$filename"
    part="$target.part"
    mkdir -p "$(dirname "$target")"
    local control_member control
    printf '[profile-builder] downloading pinned %s package %s\n' "$label" "$expected_package" >&2
    download_exact "$url" "$part" "$expected_size" "$expected_sha" "$label package $expected_package"
    [[ $(stat -f '%z' "$part") == "$expected_size" ]] \
        || die "pinned package size mismatch: $expected_package"
    [[ $(sha "$part") == "$expected_sha" ]] \
        || die "pinned package SHA-256 mismatch: $expected_package"
    control_member=$(ar -t "$part" | awk '/^control\.tar/{print; exit}')
    [[ -n "$control_member" ]] || die "pinned package has no control archive: $expected_package"
    control=$(ar -p "$part" "$control_member" | tar -xOf - ./control)
    [[ $(awk -F': ' '$1 == "Package" {print $2}' <<<"$control") == "$expected_package" ]] \
        || die "pinned package identity mismatch: $expected_package"
    [[ $(awk -F': ' '$1 == "Version" {print $2}' <<<"$control") == "$expected_version" ]] \
        || die "pinned package version mismatch: $expected_package"
    [[ $(awk -F': ' '$1 == "Architecture" {print $2}' <<<"$control") == "$expected_arch" ]] \
        || die "pinned package architecture mismatch: $expected_package"
    mv -f "$part" "$target"
}

debian_manifest="$script_dir/debian_drive_closure.tsv"
ubiquiti_manifest="$script_dir/ubiquiti_drive_packages.tsv"
[[ $(sha "$debian_manifest") == 52e38d9730228dc2e6632cccbcd777498450d2b79f0ebf1077fa34dec8d197f9 ]] \
    || die 'immutable Debian closure manifest mismatch'
[[ $(sha "$ubiquiti_manifest") == 8fdfe83b30b934cc5b00b21a9a9ec812901ac979ffd65b9985b0fd012bf31067 ]] \
    || die 'immutable Ubiquiti package manifest mismatch'
cp -p "$debian_manifest" "$payload/debian-drive-closure.tsv"
cp -p "$ubiquiti_manifest" "$payload/ubiquiti-drive-packages.tsv"

while IFS=$'\t' read -r filename package version architecture size expected_sha content_hash; do
    fetch_verified_deb "$filename" "https://snapshot.debian.org/file/$content_hash" \
        "$size" "$expected_sha" "$package" "$version" "$architecture" Debian
done < "$debian_manifest"
while IFS=$'\t' read -r filename package version architecture size expected_sha url; do
    fetch_verified_deb "$filename" "$url" "$size" "$expected_sha" \
        "$package" "$version" "$architecture" Ubiquiti
done < "$ubiquiti_manifest"

# Provide stock debootstrap a complete local mirror. Its signed Release and
# Packages verification still runs on the UNVR; downloads are completed and
# hash-checked here before any build environment is created on the console.
kbuild_manifest="$script_dir/debian_kbuild_closure.tsv"
[[ $(sha "$kbuild_manifest") == "$KBUILD_CLOSURE_SHA" ]] \
    || die 'immutable kernel-build closure manifest mismatch'
cp -p "$kbuild_manifest" "$payload/debian-kbuild-closure.tsv"
kbuild_mirror="$payload/kbuild-mirror"
kbuild_index="$kbuild_mirror/dists/bullseye/main/binary-arm64"
mkdir -p "$kbuild_index"
download_exact 'https://snapshot.debian.org/file/f255c615ff196ece00973c4570189cabaae90a50' \
    "$kbuild_mirror/dists/bullseye/InRelease" 115940 \
    7a888c9463d8c14a5fb7e8520b8ca942d0c08e5c446aa0066693131cc0e6761a 'kernel-build signed Release'
download_exact 'https://snapshot.debian.org/file/e51d491e28402486f3bc588ae5943b29db865a08' \
    "$kbuild_index/Packages.xz" 7954860 \
    71a52585dc5ca78e5d682e13fc702a077c2b14355bce020ab0ff94e4ef84107a 'kernel-build package index'
xz -dc "$kbuild_index/Packages.xz" > "$kbuild_index/Packages"
[[ $(sha "$kbuild_index/Packages") == 29a803e05ffdf9fbabe7e35d7f26eae4433f1d05301d3ef160a9ee297944a8a5 ]] \
    || die 'uncompressed kernel-build index hash mismatch'
while IFS=$'\t' read -r filename package version architecture size expected_sha content_hash; do
    fetch_verified_deb "$filename" "https://snapshot.debian.org/file/$content_hash" \
        "$size" "$expected_sha" "$package" "$version" "$architecture" kernel-build "$kbuild_mirror"
done < "$kbuild_manifest"

cp -p "$script_dir/query_drive_storage_state.js" "$payload/query-drive-storage-state"

cp -p "$script_dir/build_core_unaspro_identity_patch.js" "$payload/tools/"
cp -p "$script_dir/build_core_5x_unaspro_patch.js" "$payload/tools/"
cp -p "$script_dir/build_5x_identity_overlays.py" "$payload/tools/"
cp -p "$script_dir/patch_portal_unaspro_manifest.js" "$payload/tools/"
cp -p "$script_dir/verify_storage_ui_contract.js" "$payload/tools/"
cp -p "$script_dir/build_wsdd_5x_debs_macos.sh" "$payload/tools/"
cp -p "$script_dir/ensure_unas_identity_at_boot.sh" "$payload/ensure-unas-identity"
cp -p "$script_dir/restore_drive_after_base_update.sh" "$payload/restore-drive-after-base-update"
cp -p "$script_dir/unifi-drive-launcher" "$payload/unifi-drive-launcher"
cp -p "$script_dir/unifi-drive-ubnt-tools" "$payload/unifi-drive-ubnt-tools"
cp -p "$script_dir/guarded-fwupdate" "$payload/guarded-fwupdate"
cp -p "$script_dir/logical_unadopt.sh" "$payload/logical-unadopt"
cp -p "$script_dir/readopt_ssh_restorer.sh" "$payload/readopt-ssh-restorer"
cp -p "$script_dir/unvr-unas-drive-restore.service" "$payload/"
cp -p "$script_dir/unvr-unas-identity-restore.service" "$payload/"
cp -p "$script_dir/unvr-unas-readopt-ssh.service" "$payload/"
chmod 755 \
    "$payload/ensure-unas-identity" \
    "$payload/restore-drive-after-base-update" \
    "$payload/unifi-drive-launcher" \
    "$payload/unifi-drive-ubnt-tools" \
    "$payload/guarded-fwupdate" \
    "$payload/logical-unadopt" \
    "$payload/readopt-ssh-restorer"

grep -qx 'Type=simple' "$payload/unvr-unas-readopt-ssh.service" \
    || die 'readoption finalizer must not block multi-user.target'
! grep -qx 'Type=oneshot' "$payload/unvr-unas-readopt-ssh.service" \
    || die 'readoption finalizer reintroduced the boot-ready deadlock'
grep -q 'if console_ready && ustd_boot_ready; then' "$payload/readopt-ssh-restorer" \
    || die 'readoption finalizer is missing the authoritative USTD boot-ready gate'
! sed -n '/^ustd_boot_ready()/,/^}/p' "$payload/readopt-ssh-restorer" \
    | grep -q 'usd.service' \
    || die 'readoption boot-ready gate must not wait on guarded USD'
grep -q 'defer_drive_storage_to_user ||' "$payload/readopt-ssh-restorer" \
    || die 'readoption finalizer must leave storage creation to the user'
! grep -q '/api/v2/storage/pools\|"isForce":true' "$payload/readopt-ssh-restorer" \
    || die 'readoption finalizer must not create or force a storage pool'
grep -qx 'Type=simple' "$payload/unvr-unas-drive-restore.service" \
    || die 'Drive restore service must not block multi-user.target'
! grep -qx 'Type=oneshot' "$payload/unvr-unas-drive-restore.service" \
    || die 'Drive restore service reintroduced a boot-ready deadlock'
grep -q 'wait_for_boot_ready || fail' "$payload/restore-drive-after-base-update" \
    || die 'Drive restore helper is missing the authoritative boot-ready gate'
grep -q 'UNVR4.al324.v5.1.33.44ce47b.260909.0025' "$payload/ensure-unas-identity" \
    || die 'identity restore helper is missing the exact UNVR 5.1.33 profile'
grep -q '5.1.33' "$payload/restore-drive-after-base-update" \
    || die 'Drive restore helper is missing the logical UNAS 5.1.33 profile'
grep -q 'OS firmware updates are disabled' "$payload/guarded-fwupdate" \
    || die 'fixed-release firmware refusal policy is missing'

[[ $(sha "$payload/profiles/5.1.33/core-service.js") == a65c0736fd0abad3df5cc4cd1a42549cacc84e1b76f07ff30eff5cd1d75a774b ]] || die 'logical 5.1.33 Core hash mismatch'
[[ $(sha "$payload/profiles/5.1.33/uid-unifi-os-consoles.json") == 424c7f663a94a06557d379d47944734483ee039467ebbb3c5ea750b6f99e5f32 ]] || die '5.x UID overlay hash mismatch'
[[ $(sha "$payload/profiles/5.1.33/ulp-unifi-os-console.json") == 29c94693d4586d20352c9aee22c08fa1f8c734a68fe588905d5b590babcd78f7 ]] || die '5.x ULP overlay hash mismatch'
[[ $(sha "$payload/profiles/5.1.33/unifi-assets.tar.gz") == dce770aa3c6349721466ed4031490f0eec2695a02b325a8dbbd05aad79560e82 ]] || die '5.x asset archive hash mismatch'
[[ $(sha "$payload/profiles/5.1.33/uhd-setup-index.template.html") == 0aaab5d6d9abf579bb990293fa75ff7a75579987cb16e7429469fe365df6464e ]] || die 'official 5.x setup template hash mismatch'
[[ $(sha "$payload/profiles/5.1.33/portal-index.template.html") == 40c2f5682766359c21dd13275a41158707fa958c21882a9463154b821abf757a ]] || die 'official 5.x portal template hash mismatch'
[[ $(sha "$payload/packages/wsdd_0.8.deb") == bf96efcca6bf2993262d095e6c3cf2cbb7e527a4bf21ce747a865f5b3d7668d2 ]] || die 'UNAS 5.x wsdd package hash mismatch'
[[ $(sha "$payload/packages/wsdd-server_0.8.deb") == 32a3ee30346a49388d652ca7afcea96ef248909ff6afb8f6a04ee6e3158edbdf ]] || die 'UNAS 5.x wsdd-server package hash mismatch'
python3 "$script_dir/verify_payload_contract.py" "$payload" >&2
payload_manifest="$output_dir/.payload-SHA256SUMS"
(
    cd "$payload"
    find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$file"; done > "$payload_manifest"
    shasum -a 256 -c "$payload_manifest" >/dev/null
    mv -f "$payload_manifest" SHA256SUMS
)
find "$payload" -exec touch -h -t 202001010000 {} +
bundle="$output_dir/unvr-unas-update-profiles.tar.gz"
(
    cd "$payload"
    find . -print | LC_ALL=C sort \
        | tar --no-recursion --format=ustar --uid 0 --gid 0 --uname root --gname root -cf - -T - \
        | gzip -n > "$bundle"
)
printf 'PROFILE_BUNDLE=%s\n' "$bundle"
printf 'PROFILE_BUNDLE_SHA256=%s\n' "$(sha "$bundle")"
printf 'BASE_IMAGE=%s\n' "$unvr5"
printf 'BASE_IMAGE_SIZE=%s\n' "$UNVR5_SIZE"
printf 'BASE_IMAGE_SHA256=%s\n' "$UNVR5_SHA"
build_complete=true
