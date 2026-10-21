#!/bin/bash
# Run convert.sh with every local shortcut this fork provides:
#   - official firmware from cache/firmware (tools/fetch-firmware.sh)
#   - hash-pinned Debian packages from cache/artifacts (Git LFS)
#   - prebuilt, byte-identical kernel modules from prebuilt/modules (Git LFS)
#
#   tools/run-conversion.sh --ip 10.0.0.5 [--skip-controller-cleanup] [other convert.sh options]
set -Eeuo pipefail
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
modules="$root/prebuilt/modules/4.19.152-alpine-unvr"
artifacts="$root/cache/artifacts"

"$root/tools/fetch-firmware.sh"

if command -v git >/dev/null && git -C "$root" lfs ls-files >/dev/null 2>&1; then
    git -C "$root" lfs pull --include 'prebuilt/**,cache/artifacts/**' >/dev/null 2>&1 || true
fi
args=(
    --unvr-5-firmware "$root/cache/firmware/UNVR-5.1.33.bin"
    --unas-5-firmware "$root/cache/firmware/UNASPRO-5.1.33.bin"
)
if (cd "$modules" 2>/dev/null && shasum -a 256 -c --quiet SHA256SUMS 2>/dev/null); then
    args+=(--prebuilt-modules "$modules")
else
    echo 'prebuilt modules missing or not pulled from LFS; the UNVR will compile them (slower)' >&2
fi
if [[ -f "$artifacts/payload/kbuild-mirror/dists/bullseye/InRelease" ]] &&
   ! head -c 64 "$artifacts/payload/kbuild-mirror/dists/bullseye/InRelease" | grep -q 'git-lfs'; then
    args+=(--artifact-cache "$artifacts")
else
    echo 'Debian package cache missing or not pulled from LFS; packages will be downloaded' >&2
fi

cd "$root"
exec caffeinate -dims ./convert.sh install "${args[@]}" "$@"
