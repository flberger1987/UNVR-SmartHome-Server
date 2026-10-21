#!/bin/bash
# Rebuild zstd_compress.ko, btrfs.ko and fuse.ko for the UNVR 5.1.33 kernel in a
# Debian bullseye arm64 container (Docker on an Apple Silicon Mac takes ~1-2 min)
# and check them against the converter's pinned hashes.
#
# The kernel configuration is read straight out of the official UNVR 5.1.33
# kernel image (CONFIG_IKCONFIG), so no access to a UNVR is needed. The result
# replaces prebuilt/modules/4.19.152-alpine-unvr/ only if all three files are
# byte-identical to the validated on-device build.
set -Eeuo pipefail
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
dest="$root/prebuilt/modules/4.19.152-alpine-unvr"
image=debian:bullseye-20240812   # older than the pinned 2024-09-01 snapshot, so apt only upgrades

command -v docker >/dev/null || { echo 'docker is required' >&2; exit 1; }
"$root/tools/fetch-firmware.sh"

work=$(mktemp -d "${TMPDIR:-/tmp}/unvr-kbuild.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
python3 -I - "$root/cache/firmware/UNVR-5.1.33.bin" "$work/config" <<'PY'
import gzip, hashlib, struct, sys, zlib
firmware, out = sys.argv[1:3]
data = open(firmware, 'rb').read(16 * 1024 * 1024)
best = None
offset = 0
while (i := data.find(b'\x27\x05\x19\x56', offset)) >= 0:   # legacy uImage header
    size = struct.unpack('>I', data[i + 12:i + 16])[0]
    if 0 < size < 40_000_000 and (best is None or size > best[1]):
        best = (i, size)
    offset = i + 4
if best is None:
    sys.exit('kernel uImage not found in firmware')
kernel = gzip.decompress(data[best[0] + 64:best[0] + 64 + best[1]])
start = kernel.find(b'IKCFG_ST')
if start < 0:
    sys.exit('embedded kernel configuration not found')
config = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(kernel[start + 8:])
expected = '6e7bcbc5c1779103dfadcf7b49a1c3e50e49c647bb0284ff478781e0888b3f6c'
if hashlib.sha256(config).hexdigest() != expected:
    sys.exit('extracted kernel configuration does not match the pinned UNVR 5.1.33 config')
open(out, 'wb').write(config)
PY
cp "$root/tools/kbuild/build-in-container.sh" "$work/"

docker run --rm --platform linux/arm64 \
    --tmpfs /usr/src:rw,exec,size=3g \
    -e JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}" \
    -v "$work:/out" "$image" bash /out/build-in-container.sh | tee "$work/build.log"

if [[ $(grep -c '^IDENTICAL' "$work/build.log") -ne 3 ]]; then
    echo 'modules are not byte-identical to the validated build; prebuilt/ left unchanged' >&2
    exit 1
fi
mkdir -p "$dest"
cp "$work/zstd_compress.ko" "$work/btrfs.ko" "$work/fuse.ko" "$dest/"
(cd "$dest" && shasum -a 256 btrfs.ko fuse.ko zstd_compress.ko > SHA256SUMS)
mkdir -p "$dest/extra"
cp "$work/macvlan.ko" "$dest/extra/"
(cd "$dest/extra" && shasum -a 256 macvlan.ko > SHA256SUMS)
echo "prebuilt modules updated in $dest (extra/macvlan.ko for extras/unas-apps)"
