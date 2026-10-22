#!/bin/bash
# Save a recovery set on the UNAS pool (run on the Mac): the finished images
# of every stack, the stack configuration with the console identities,
# LoxBerry's data and the newest UniFi Network backups. With it the apps come
# back without rebuilding anything (see docs/RECOVERY.md, restore-unas.sh).
#
#   extras/unas-apps/backup-unas.sh root@<UNAS-IP>
#
# UniFi OS installs its apps (Protect, Network updates, ...) into the
# container's own file layer, not into the data volumes; the built image
# does not have them. The UniFi OS containers (unifi-os, unifi-protect) are
# therefore first committed to <image>-live and that image is saved instead;
# restore-unas.sh loads it under the image name the stack uses. Run this after
# installing or updating apps in UniFi OS.
#
# Result in <pool>/.unas-apps/backup/recovery/ (images that did not change
# since the last run are skipped):
#   images/<image>.tar.zst      docker save of each image the stacks use
#                               (<image>-live for the UniFi OS containers)
#   config.tar.zst              stacks (compose.yaml, .env, resolv.conf), Dockge,
#                               identities of the UniFi OS containers, daemon.json
#   host-files.tar.zst          host units/scripts/settings, for reference
#   loxberry-volume.tar.zst     LoxBerry's /opt/loxberry volume
#   network/                    newest UniFi Network backups (.unf)
#   MANIFEST.txt, SHA256SUMS
#
# The set lives on the same disks as the apps: it covers a lost or reset boot
# medium, not the loss of the RAID. Copy the directory elsewhere as well.
set -Eeuo pipefail
target=${1:?usage: $0 root@<UNAS-IP>}
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

remote 'bash -s' <<'EOF'
set -euo pipefail
volume=$(for v in /volume/*-*-*-*-*; do mountpoint -q "$v" && echo "$v" && break; done)
[ -n "$volume" ] || { echo 'no mounted storage pool' >&2; exit 1; }
A="$volume/.unas-apps" B="$volume/.unas-apps/backup/recovery"
mkdir -p "$B/images" "$B/network"
z() { nice -n 19 ionice -c3 zstd -T2 -6 -q "$@"; }

# images of all stacks (also those in optional profiles)
images=$(sed -n 's/^ *image: *\([^ #"]*\).*/\1/p' "$A"/data/stacks/*/compose.yaml "$A"/dockge/compose.yaml | sort -u)
# UniFi OS containers: freeze the container layer (installed apps) as <image>-live
for c in unifi-os unifi-protect; do
    docker container inspect "$c" >/dev/null 2>&1 || continue
    base=$(docker container inspect -f '{{.Config.Image}}' "$c")
    base=$(grep -x -F "$base" <<< "$images" || docker image inspect -f '{{index .RepoTags 0}}' "$base" 2>/dev/null || true)
    [ -n "$base" ] || { echo "cannot tell the image of $c (skipped)"; continue; }
    docker commit --pause=false -m "live state of $c, $(date -Is)" "$c" "$base-live" >/dev/null
    images=$(sed "s|^$base\$|$base-live|" <<< "$images")
    rm -f "$B/images/$(echo "$base" | tr '/:' '__').tar.zst"*
    echo "committed $c -> $base-live"
done
for img in $images; do
    id=$(docker image inspect -f '{{.Id}}' "$img" 2>/dev/null) || { echo "missing image $img (skipped)"; continue; }
    f="$B/images/$(echo "$img" | tr '/:' '__').tar.zst"
    if [ -f "$f" ] && [ "$(cat "$f.id" 2>/dev/null)" = "$id" ]; then echo "unchanged $img"; continue; fi
    docker save "$img" | z -o "$f.part" && mv "$f.part" "$f" && echo "$id" > "$f.id"
    echo "saved $img ($(du -h "$f" | cut -f1))"
done

# stack configuration and identities (relative to <pool>/.unas-apps)
(cd "$A" && tar -cf - --ignore-failed-read \
    data/stacks dockge docker/daemon.json \
    $(ls -d uckp/system.info uckp/board.info uckp/mtd protect/system.info protect/board.info 2>/dev/null) \
    ) | z -o "$B/config.tar.zst.part" && mv "$B/config.tar.zst.part" "$B/config.tar.zst"

# host files for reference (recreated by the install scripts)
tar -C / -cf - --ignore-failed-read $(cd / && ls -d usr/local/sbin/unas-* usr/local/bin/docker \
    etc/systemd/system/unas-* etc/systemd/system/var-tmp.mount etc/systemd/journald.conf.d/90-unas-* \
    etc/postgresql/14/main/conf.d/90-unas-* root/.ssh/authorized_keys 2>/dev/null) 2>/dev/null \
    | z -o "$B/host-files.tar.zst.part" && mv "$B/host-files.tar.zst.part" "$B/host-files.tar.zst"

# private system sheet (addresses, identities, ...), if kept next to the set
[ -f "$A/backup/SYSTEM.md" ] && cp -p "$A/backup/SYSTEM.md" "$B/SYSTEM.md"

# LoxBerry's data volume
lv=$(docker volume inspect -f '{{.Mountpoint}}' unas-apps_loxberry 2>/dev/null || true)
[ -n "$lv" ] && tar -C "$lv" -cf - --warning=no-file-changed . 2>/dev/null \
    | z -o "$B/loxberry-volume.tar.zst.part" && mv "$B/loxberry-volume.tar.zst.part" "$B/loxberry-volume.tar.zst"

# newest Network backups: UniFi OS container, standalone controller
for d in "$A"/uckp/data/unifi/data/backup/autobackup "$A"/data/unifi-network-application/data/backup/autobackup; do
    [ -d "$d" ] || continue
    { ls -t "$d"/*.unf 2>/dev/null || true; } | head -2 | while read -r f; do cp -p "$f" "$B/network/"; done
done
{ ls -t "$B"/network/*.unf 2>/dev/null || true; } | tail -n +7 | xargs -r rm -f

{
    echo "recovery set, $(date -Is)"
    echo "host: $(cat /usr/lib/version), kernel $(uname -r), docker $(docker version -f '{{.Server.Version}}' 2>/dev/null)"
    echo
    echo "images:"
    for f in "$B"/images/*.tar.zst; do printf '  %-60s %8s  %s\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)" "$(cut -c1-19 "$f.id")"; done
    echo
    echo "identities:"
    for c in uckp protect; do
        [ -f "$A/$c/board.info" ] && echo "  $c: $(grep -E '^board\.(shortname|sysid|serialno)=' "$A/$c/board.info" | paste -sd' ')" || true
    done
    echo
    echo "stacks (.env without secrets):"
    for e in "$A"/data/stacks/*/.env; do
        echo "  $(basename "$(dirname "$e")"): $({ grep -v -E 'PASS|SECRET|KEY' "$e" || true; } | { grep -E '_IP=|_MAC=|LAN_' || true; } | paste -sd' ')"
    done
} > "$B/MANIFEST.txt"
(cd "$B" && find . -type f ! -name '*.id' ! -name SHA256SUMS ! -name '*.part' -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
echo "recovery set: $B ($(du -sh "$B" | cut -f1))"
EOF
