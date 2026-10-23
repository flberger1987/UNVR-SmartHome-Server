#!/bin/bash
# Prepare everything the converted UNVR needs for its apps, on a Mac with Docker
# (Apple Silicon builds arm64 natively):
#   cache/unas-apps/: static Docker, Compose and crun for aarch64
#   local Docker images: MongoDB, UniFi Network, LoxBerry, Dockge (arm64)
# install-on-unas.sh --images streams the images straight into the UNAS, so no
# multi-GB tarball is written. Nothing here is committed (third-party software).
set -Eeuo pipefail
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
out="$root/cache/unas-apps"
mkdir -p "$out"

# The LoxBerry build needs about 8 GB in Docker's disk image while it exports;
# a full disk stops Docker Desktop in the middle of the build.
free_kib=$(df -Pk "$HOME" | awk 'NR == 2 {print $4}')
(( free_kib >= 8 * 1024 * 1024 )) || { echo 'at least 8 GB free disk space is needed for the image builds' >&2; exit 1; }

docker_version=28.5.2   # last line without the cgroup v1 deprecation of v29
compose_version=v5.6.1
crun_version=1.30.1
mongo_image=mongo:4.4.18
unifi_image=lscr.io/linuxserver/unifi-network-application:10.6.106-ls151
dockge_image=louislam/dockge:1
loxberry_image=loxberry-unas:3.0.1.3

fetch() {   # url file [sha256-url]
    [[ -f "$out/$2" ]] && return
    curl -fL -o "$out/$2.part" "$1"
    if [[ -n "${3:-}" ]]; then
        [[ "$(shasum -a 256 "$out/$2.part" | cut -d' ' -f1)" == "$(curl -fsSL "$3" | cut -d' ' -f1)" ]] \
            || { echo "checksum mismatch: $2" >&2; exit 1; }
    fi
    mv "$out/$2.part" "$out/$2"
}
echo "== Docker ${docker_version}, Compose ${compose_version}, crun ${crun_version} (aarch64)"
fetch "https://download.docker.com/linux/static/stable/aarch64/docker-${docker_version}.tgz" "docker-${docker_version}.tgz"
fetch "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-aarch64" docker-compose \
      "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-aarch64.sha256"
fetch "https://github.com/containers/crun/releases/download/${crun_version}/crun-${crun_version}-linux-arm64" crun
chmod 755 "$out/docker-compose" "$out/crun"

echo "== pulling ${mongo_image}, ${unifi_image}, ${dockge_image} (linux/arm64)"
for image in "$mongo_image" "$unifi_image" "$dockge_image"; do
    docker pull --platform linux/arm64 "$image"
done

echo "== building LoxBerry 3.0.1.3 (base, then UNAS overlay)"
docker build --platform linux/arm64 -t loxberry-arm64:base "$here/loxberry/base"
docker build --platform linux/arm64 -t "$loxberry_image" "$here/loxberry"
docker tag "$loxberry_image" loxberry-unas:live   # the stack runs :live (see docker-compose.yml)

(cd "$out" && shasum -a 256 "docker-${docker_version}.tgz" docker-compose crun > SHA256SUMS)
docker image ls --format '{{.Repository}}:{{.Tag}}  {{.Size}}' |
    grep -E "^(mongo:4.4.18|lscr.io/linuxserver/unifi|louislam/dockge|loxberry-unas)" || true
