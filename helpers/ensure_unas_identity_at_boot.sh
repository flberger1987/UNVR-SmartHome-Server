#!/bin/bash

# Reapply the scoped UNAS userspace identity after the stock UNVR updater
# replaces /usr and selected /etc paths. This script never writes firmware,
# bootloader, EEPROM, partitions, RAID metadata, filesystems, or /volume1.

set -Eeuo pipefail
export LC_ALL=C
umask 077

readonly runtime=/data/unvr-unas-runtime
readonly profiles=$runtime/profiles
readonly log_file=$runtime/identity-restore.log
readonly physical_version_file=/usr/lib/version

sha256() {
    sha256sum "$1" | awk '{print $1}'
}

log() {
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$log_file"
}

fail() {
    log "REFUSED: $*"
    exit 1
}

hash_allowed() {
    local actual=$1
    shift
    local allowed
    for allowed in "$@"; do
        [[ "$actual" == "$allowed" ]] && return 0
    done
    return 1
}

ensure_file() {
    local source=$1 target=$2 desired=$3 mode=$4
    shift 4
    local source_hash current tmp
    [[ -f "$source" && ! -L "$source" ]] || fail "missing or unsafe staged identity artifact: $source"
    source_hash=$(sha256 "$source")
    [[ "$source_hash" == "$desired" ]] || fail "staged identity artifact hash mismatch: $source"
    [[ ! -L "$target" && ( ! -e "$target" || -f "$target" ) ]] \
        || fail "identity target is not a safe regular file: $target"
    current=MISSING
    [[ ! -f "$target" ]] || current=$(sha256 "$target")
    [[ "$current" == "$desired" ]] && return 0
    hash_allowed "$current" MISSING "$@" || fail "unrecognized target before identity restore: $target"
    tmp=$(mktemp "${target}.unas-restore.XXXXXX")
    install -o root -g root -m "$mode" "$source" "$tmp"
    [[ "$(sha256 "$tmp")" == "$desired" ]] || fail "staged target hash mismatch: $target"
    mv -f "$tmp" "$target"
    log "restored $(basename "$target")"
}

ensure_drive_scoped_tool_5x() {
    local source=/sbin/ubnt-tools target=$runtime/drive-bin/real/ubnt-tools
    [[ -f "$source" && ! -L "$source" && -x "$source" ]] \
        || fail "stock ubnt-tools executable is missing or unsafe"
    [[ "$(sha256 "$source")" == b158615d9ba1d21a31c29e923d3be23796c95c43cadea2b73e1ce1460e18058e ]] \
        || fail "stock ubnt-tools executable is not the validated 5.1 build"
    if [[ -e "$target" ]]; then
        [[ -f "$target" && ! -L "$target" && -x "$target" ]] \
            || fail "Drive-scoped stock ubnt-tools pass-through is unsafe"
        [[ "$(sha256 "$target")" == b158615d9ba1d21a31c29e923d3be23796c95c43cadea2b73e1ce1460e18058e ]] \
            || fail "Drive-scoped stock ubnt-tools pass-through changed"
        return
    fi
    install -d -m 0755 "$(dirname "$target")"
    install -o root -g root -m 0755 "$source" "$target"
    [[ "$(sha256 "$target")" == b158615d9ba1d21a31c29e923d3be23796c95c43cadea2b73e1ce1460e18058e ]] \
        || fail "Drive-scoped stock ubnt-tools pass-through copy failed"
}

ensure_generated_manifest_template() {
    local source=$1 target=$2 template_hash=$3 generated_hash=$4 stock_generated_hash=$5
    local source_hash current tmp
    [[ -f "$source" && ! -L "$source" ]] || fail "missing or unsafe official manifest template: $source"
    source_hash=$(sha256 "$source")
    [[ "$source_hash" == "$template_hash" ]] || fail "official manifest template hash mismatch: $source"
    [[ -f "$target" && ! -L "$target" ]] || fail "manifest target is missing or unsafe: $target"
    current=$(sha256 "$target")
    case "$current" in
        "$template_hash"|"$generated_hash") return 0 ;;
        "$stock_generated_hash") ;;
        *) fail "unrecognized generated manifest target: $target" ;;
    esac
    tmp=$(mktemp "${target}.unas-template.XXXXXX")
    install -o root -g root -m 0644 "$source" "$tmp"
    [[ "$(sha256 "$tmp")" == "$template_hash" ]] || fail "manifest template staging failed: $target"
    mv -f "$tmp" "$target"
    log "restored official manifest template for $(basename "$(dirname "$target")")"
}

ensure_asset_modes() {
    local target=$1
    find "$target" -type d -exec chmod 0755 {} +
    find "$target" -type f -exec chmod 0644 {} +
}

verify_asset_overlay() {
    local archive=$1 target=$2 desired_manifest=$3 stage file relative
    [[ -d "$target" && ! -L "$target" ]] || fail "asset target is missing or unsafe: $target"
    stage=$(mktemp -d /usr/share/.unifi-assets-verify.XXXXXX)
    trap 'rm -rf -- "$stage"' RETURN EXIT HUP INT TERM
    tar -C "$stage" -xzf "$archive"
    [[ -z "$(find "$stage" -type l -print -quit)" ]] || fail "staged asset archive contains a symlink"
    [[ -f "$stage/manifest.json" && "$(sha256 "$stage/manifest.json")" == "$desired_manifest" ]] \
        || fail "staged asset manifest hash mismatch"
    while IFS= read -r -d '' file; do
        relative=${file#"$stage"/}
        [[ -f "$target/$relative" && ! -L "$target/$relative" ]] \
            || fail "installed asset is missing or unsafe: $relative"
        [[ "$(sha256 "$target/$relative")" == "$(sha256 "$file")" ]] \
            || fail "installed asset hash mismatch: $relative"
    done < <(find "$stage" -type f -print0)
    rm -rf -- "$stage"
    trap - RETURN EXIT HUP INT TERM
}

install_asset_overlay() {
    local archive=$1 target=$2 desired_manifest=$3 stage manifest_tmp
    [[ -d "$target" && ! -L "$target" ]] || fail "asset target is missing or unsafe: $target"
    stage=$(mktemp -d /usr/share/.unifi-assets-stage.XXXXXX)
    trap 'rm -rf -- "$stage"; [[ -z "${manifest_tmp:-}" ]] || rm -f -- "$manifest_tmp"' RETURN EXIT HUP INT TERM
    tar -C "$stage" -xzf "$archive"
    [[ -f "$stage/manifest.json" && ! -L "$stage/manifest.json" ]] \
        || fail "staged asset manifest is missing or unsafe"
    [[ -z "$(find "$stage" -type l -print -quit)" ]] || fail "staged asset archive contains a symlink"
    [[ "$(sha256 "$stage/manifest.json")" == "$desired_manifest" ]] \
        || fail "staged asset manifest hash mismatch"
    ensure_asset_modes "$stage"
    tar -C "$stage" --exclude='./manifest.json' -cf - . | tar -C "$target" -xf -
    manifest_tmp=$(mktemp "$target/.manifest.json.XXXXXX")
    install -o root -g root -m 0644 "$stage/manifest.json" "$manifest_tmp"
    [[ "$(sha256 "$manifest_tmp")" == "$desired_manifest" ]] \
        || fail "asset manifest staging failed"
    mv -f "$manifest_tmp" "$target/manifest.json"
    ensure_asset_modes "$target"
    rm -rf -- "$stage"
    trap - RETURN EXIT HUP INT TERM
    verify_asset_overlay "$archive" "$target" "$desired_manifest"
}

ensure_asset_backup() {
    local target=$1 backup=$2 expected_manifest=$3 tmp embedded_hash
    if [[ -e "$backup" ]]; then
        [[ -f "$backup" && ! -L "$backup" ]] || fail "asset rollback backup is unsafe: $backup"
        tar -tzf "$backup" >/dev/null || fail "asset rollback backup is corrupt: $backup"
        embedded_hash=$(tar -xOzf "$backup" ./manifest.json | sha256sum | awk '{print $1}')
        [[ "$embedded_hash" == "$expected_manifest" ]] \
            || fail "asset rollback backup manifest mismatch: $backup"
        return
    fi
    tmp=$(mktemp "${backup}.XXXXXX")
    trap 'rm -f -- "$tmp"' RETURN EXIT HUP INT TERM
    tar -C "$target" -czf "$tmp" .
    tar -tzf "$tmp" >/dev/null || fail "new asset rollback backup is corrupt"
    embedded_hash=$(tar -xOzf "$tmp" ./manifest.json | sha256sum | awk '{print $1}')
    [[ "$embedded_hash" == "$expected_manifest" ]] || fail "new asset rollback backup manifest mismatch"
    chmod 0600 "$tmp"
    mv -f "$tmp" "$backup"
    trap - RETURN EXIT HUP INT TERM
}

ensure_drive_scoped_system_info() {
    local source=/proc/ubnthal/system.info target=$runtime/drive-system.info tmp
    [[ -f "$source" ]] || fail "physical system information is unavailable"
    [[ "$(grep -c '^shortname=' "$source")" -eq 1 ]] || fail "physical shortname record is ambiguous"
    [[ "$(grep -c '^name=' "$source")" -eq 1 ]] || fail "physical product-name record is ambiguous"
    [[ "$(sed -n 's/^shortname=//p' "$source")" == UNVR4 ]] || fail "physical system is not the validated four-bay UNVR"
    [[ ! -L "$target" && ( ! -e "$target" || -f "$target" ) ]] \
        || fail "Drive-scoped system information target is unsafe"
    tmp=$(mktemp "$runtime/.drive-system.info.XXXXXX")
    trap 'rm -f -- "${tmp:-}"' RETURN EXIT HUP INT TERM
    awk -F= '
        $1 == "shortname" { print "shortname=UNASPRO"; next }
        $1 == "name"      { print "name=UniFi Network Attached Storage Pro"; next }
        { print }
    ' "$source" > "$tmp"
    [[ "$(grep -c '^shortname=UNASPRO$' "$tmp")" -eq 1 ]] \
        || fail "Drive-scoped shortname generation failed"
    [[ "$(grep -c '^name=UniFi Network Attached Storage Pro$' "$tmp")" -eq 1 ]] \
        || fail "Drive-scoped product-name generation failed"
    install -o root -g root -m 0644 "$tmp" "$target.new"
    mv -f "$target.new" "$target"
    rm -f -- "$tmp"
    trap - RETURN EXIT HUP INT TERM
}

ensure_assets_5x() {
    local archive=$profiles/5.1.33/unifi-assets.tar.gz
    local archive_hash=dce770aa3c6349721466ed4031490f0eec2695a02b325a8dbbd05aad79560e82
    local target=/usr/share/unifi-assets
    local stock_manifest=4bf51b9f1f8f04350e8401b7898112bd69f723b14a84a1fd30b04d805dd54f20
    local previous_manifest=ff97555250780a6979d88bd20474dabfd96d28a97cac246a20038fdd4fe8c133
    local desired_manifest=62374925f7f36926d00f65e32f9ac9195dbb55d71d5741e1a94028927e202a05
    local current_manifest=MISSING backup_dir=$runtime/identity-backup-5.1.33
    [[ -f "$archive" && "$(sha256 "$archive")" == "$archive_hash" ]] || fail "UNAS 5.x asset archive is missing or altered"
    [[ ! -f "$target/manifest.json" ]] || current_manifest=$(sha256 "$target/manifest.json")
    if [[ "$current_manifest" == "$desired_manifest" ]]; then
        verify_asset_overlay "$archive" "$target" "$desired_manifest"
        ensure_asset_modes "$target"
        return 0
    fi
    hash_allowed "$current_manifest" "$stock_manifest" "$previous_manifest" || fail "unrecognized 5.x asset manifest"
    mkdir -p "$backup_dir"
    ensure_asset_backup "$target" "$backup_dir/unifi-assets-unvr.tar.gz" "$current_manifest"
    install_asset_overlay "$archive" "$target" "$desired_manifest"
    [[ "$(sha256 "$target/manifest.json")" == "$desired_manifest" ]] || fail "UNAS 5.x asset restore failed"
    log "restored official UNAS Pro 5.x assets"
}

ensure_assets_4x() {
    local logical_profile=${1:-4.1.22}
    local archive=$profiles/$logical_profile/unifi-assets.tar.gz
    local archive_hash=07f69486e5ff08b34ee7f55ce19cfcd3658e992b3fa90eb3b5483a0d82447208
    local target=/usr/share/unifi-assets
    local stock_manifest=4bf51b9f1f8f04350e8401b7898112bd69f723b14a84a1fd30b04d805dd54f20
    local desired_manifest=ff97555250780a6979d88bd20474dabfd96d28a97cac246a20038fdd4fe8c133
    local current_manifest=MISSING backup_dir=$runtime/identity-backup-4.1.22
    [[ -f "$archive" && "$(sha256 "$archive")" == "$archive_hash" ]] || fail "UNAS $logical_profile asset archive is missing or altered"
    [[ ! -f "$target/manifest.json" ]] || current_manifest=$(sha256 "$target/manifest.json")
    if [[ "$current_manifest" == "$desired_manifest" ]]; then
        verify_asset_overlay "$archive" "$target" "$desired_manifest"
        ensure_asset_modes "$target"
        return 0
    fi
    hash_allowed "$current_manifest" "$stock_manifest" || fail "unrecognized 4.1.22 asset manifest"
    mkdir -p "$backup_dir"
    ensure_asset_backup "$target" "$backup_dir/unifi-assets-unvr-restore.tar.gz" "$current_manifest"
    install_asset_overlay "$archive" "$target" "$desired_manifest"
    [[ "$(sha256 "$target/manifest.json")" == "$desired_manifest" ]] || fail "UNAS 4.1.22 asset restore failed"
    log "restored official UNAS Pro $logical_profile assets"
}

[[ -f "$physical_version_file" ]] || fail "physical firmware version is unavailable"
physical_version=$(cat "$physical_version_file")

[[ "$physical_version" == UNVR4.al324.v5.1.33.44ce47b.260909.0025 ]] \
    || fail "identity restore requires the pinned physical UNVR 5.1.33 baseline"
ensure_drive_scoped_tool_5x
[[ "$(uname -r)" == 4.19.152-alpine-unvr ]] || fail "unexpected UNVR kernel"
[[ "$(cat "$runtime/logical-target" 2>/dev/null || true)" == 5.1.33 ]] \
    || fail "logical UNAS target is not the pinned 5.1.33 release"
    ensure_file \
        "$profiles/5.1.33/core-service.js" \
        /usr/share/unifi-core/app/service.js \
        a65c0736fd0abad3df5cc4cd1a42549cacc84e1b76f07ff30eff5cd1d75a774b \
        0644 \
        14975b7bc2758e0e76d19e1d084a7d8d9da1881f1553f61febc6f9fd0e013eac \
        9def42c03b368a9434b1b3d5ee48f7a295bae616ae1060639f4c53c4e292fbb0 \
        53cfc610717f19301b5b0d64fc40619481d06d3f3852d89f63ba9657625aaf80 \
        63418097587b8aae9373ed1dafcf7e9a4c671e49b400d35474015a937b538c57 \
        062aaf21d1f9e59c1df4193f185de8d0b0e01a343dfd41e4dbd06f3e4adb5915
    ensure_assets_5x
    ensure_generated_manifest_template \
        "$profiles/5.1.33/uhd-setup-index.template.html" \
        /usr/share/unifi-core/app/node_modules/@ubnt/uhd-setup/dist/index.html \
        0aaab5d6d9abf579bb990293fa75ff7a75579987cb16e7429469fe365df6464e \
        cff883330a7bb3ab378053ddd9611f22efea8a4ff22863f9cfd59aeda0fa831c \
        1a54b4ab597ab899a58dea289de7f47c009e1d42fd87ebc02b214857455c126b
    ensure_generated_manifest_template \
        "$profiles/5.1.33/portal-index.template.html" \
        /usr/share/unifi-core/app/node_modules/@ubnt/unifi-portal/dist/local/index.html \
        40c2f5682766359c21dd13275a41158707fa958c21882a9463154b821abf757a \
        8e81c708d68c18385139422d1ab34d95a2d5a4a538d47797db2c8d15a6542d1c \
        84bcb7afe181bab2fcc9707b0cd36c05cc7ec0a854cab81232edb6b2bedfe7dc
    ensure_file \
        "$profiles/5.1.33/uid-unifi-os-consoles.json" \
        /usr/lib/uid-agent/unifi-os-consoles.json \
        424c7f663a94a06557d379d47944734483ee039467ebbb3c5ea750b6f99e5f32 \
        0644 \
        a7db66c52b418eb39bc2f66f5fc73f5a55083237863ffec50f921ecf303dbe35
    ensure_file \
        "$profiles/5.1.33/ulp-unifi-os-console.json" \
        /usr/lib/ulp-go/unifi-os-console.json \
        29c94693d4586d20352c9aee22c08fa1f8c734a68fe588905d5b590babcd78f7 \
        0644 \
        4accb0af048a5a52deb9ff0c60a0fb98c72d9a4efd0fa7e48721117f94bdad1b

ensure_drive_scoped_system_info
[[ -x "$runtime/guarded-fwupdate" ]] || fail "guarded firmware boundary is missing"
[[ -x "$runtime/unifi-drive-launcher" ]] || fail "version-gated Drive launcher is missing"
[[ -x "$runtime/drive-bin/ubnt-tools" ]] || fail "Drive-scoped identity adapter is missing"
[[ -x "$runtime/drive-bin/real/ubnt-tools" ]] || fail "Drive-scoped stock ubnt-tools pass-through is missing"
sync
log "UNAS identity ready for physical firmware $physical_version"
