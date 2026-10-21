#!/bin/bash
# Download the two official firmware images the conversion needs into
# cache/firmware/ and verify them against their pinned size and SHA-256.
# The images are Ubiquiti's and are never committed to this repository.
set -Eeuo pipefail
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
dest="$root/cache/firmware"
mkdir -p "$dest"

fetch() {
    local name=$1 url=$2 size=$3 sha=$4 file="$dest/$1"
    if [[ -f "$file" && $(stat -f '%z' "$file") == "$size" && $(shasum -a 256 "$file" | cut -d' ' -f1) == "$sha" ]]; then
        echo "ok      $name (cached)"
        return
    fi
    echo "fetch   $name"
    curl -fL --proto '=https' --tlsv1.2 --retry 5 --retry-delay 3 -C - -o "$file.part" "$url"
    [[ $(stat -f '%z' "$file.part") == "$size" ]] || { echo "size mismatch: $name" >&2; exit 1; }
    [[ $(shasum -a 256 "$file.part" | cut -d' ' -f1) == "$sha" ]] || { echo "SHA-256 mismatch: $name" >&2; exit 1; }
    mv -f "$file.part" "$file"
    echo "ok      $name"
}

fetch UNVR-5.1.33.bin \
    https://fw-download.ubnt.com/data/unifi-nvr/976a-UNVR-5.1.33-84c520f3-fb97-41e0-be2b-b0f89c46c7b8.bin \
    787559347 b170e97f9b7a703947380aed1108221e70ab18074b986906aca9df10891ca1e0
fetch UNASPRO-5.1.33.bin \
    https://fw-download.ubnt.com/data/unifi-drive/7a07-UNASPRO-5.1.33-10b23dea-e891-4699-bd66-3ecff7f954db.bin \
    693903010 0d711a42b68649bf2a9e129123211e59896d8b29860d85c8c43b4e98d2c59d66
