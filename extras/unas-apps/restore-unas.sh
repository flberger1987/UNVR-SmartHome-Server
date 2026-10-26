#!/bin/bash
# Bring the apps back from a recovery set made by backup-unas.sh (run on the Mac).
#
#   extras/unas-apps/restore-unas.sh root@<UNAS-IP> [--set <dir on the UNAS>] [--check]
#
#   --check   only verify the set (checksums, every archive decompresses, the
#             Protect zips and Home Assistant backups are readable), change nothing
#
# The app backups in the set (network/*.unf, protect/*.zip, unifi-os/*.unifi,
# homeassistant/*.tar) are restored in UniFi OS and Home Assistant themselves;
# the script lists them (docs/RECOVERY.md).
#
# Order (docs/RECOVERY.md): converted UNAS with a storage pool, host tuning,
# install-on-unas.sh (Docker), then this script, then install-uckp.sh /
# install-protect.sh (they keep the restored identity and use the loaded
# image) and install-on-unas.sh --up.
#
# Default set: <pool>/.unas-apps/backup/recovery. After rebuilding the pool,
# copy the set back to that place first. Existing files are never overwritten.
set -Eeuo pipefail
usage="usage: $0 root@<UNAS-IP> [--set <dir on the UNAS>] [--check]"
target=${1:?$usage}
shift
set_dir='' check=false
while (( $# )); do
    case "$1" in
        --set) set_dir=${2:?$usage}; shift ;;
        --check) check=true ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

remote "SET='$set_dir' CHECK='$check' bash -s" <<'EOF'
set -euo pipefail
volume=$(for v in /volume/*-*-*-*-*; do mountpoint -q "$v" && echo "$v" && break; done)
[ -n "$volume" ] || { echo 'no mounted storage pool; create one in UniFi Drive first' >&2; exit 1; }
A="$volume/.unas-apps"
B=${SET:-$A/backup/recovery}
[ -f "$B/SHA256SUMS" ] || { echo "no recovery set in $B" >&2; exit 1; }

echo "checking $B"
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || { echo 'checksum mismatch: the set is damaged' >&2; exit 1; }
echo "checksums OK ($(wc -l < "$B/SHA256SUMS") files)"
if [ "$CHECK" = true ]; then
    bad=0
    ok() { echo "  ok  ${1#"$B"/} ($(du -h "$1" | cut -f1)${2:+; $2})"; }
    for f in "$B"/*.tar.zst "$B"/images/*.tar.zst; do
        [ -e "$f" ] || continue
        if zstd -t -q "$f"; then ok "$f"; else echo "  BAD ${f#"$B"/}"; bad=$((bad + 1)); fi
    done
    # Protect: every member's CRC, and the settings file it cannot do without
    for f in "$B"/protect/*.zip; do
        [ -e "$f" ] || continue
        if python3 -c 'import sys, zipfile; z = zipfile.ZipFile(sys.argv[1]); sys.exit(z.testzip() is not None or "nvr.json" not in z.namelist())' "$f"; then
            ok "$f"
        else echo "  BAD ${f#"$B"/}"; bad=$((bad + 1)); fi
    done
    # console backups are encrypted: checksum only, contents from their metadata
    for f in "$B"/unifi-os/*.unifi; do
        [ -e "$f" ] || continue
        apps=$(jq -r '[(.controllers // {}), (.services // {}) | to_entries[] | "\(.key) \(if .value.success then "ok" else "FAILED" end)"] | join(", ")' \
            "${f%.unifi}.metadata.json" 2>/dev/null || echo 'contents unknown')
        if [ -s "$f" ]; then ok "$f" "$apps"; else echo "  BAD ${f#"$B"/} (empty)"; bad=$((bad + 1)); fi
    done
    for f in "$B"/network/*.unf; do [ -e "$f" ] || continue; ok "$f" 'checksum only'; done
    # Home Assistant: the tar and its unencrypted backup.json (the inner archive is encrypted)
    for f in "$B"/homeassistant/*.tar; do
        [ -e "$f" ] || continue
        if info=$(tar -xOf "$f" ./backup.json 2>/dev/null | jq -r '"\(.name), \(.date[:16])\(if .protected then ", encrypted" else "" end)"' 2>/dev/null) && [ -n "$info" ]; then
            ok "$f" "$info"
        else echo "  BAD ${f#"$B"/}"; bad=$((bad + 1)); fi
    done
    head -n 3 "$B/MANIFEST.txt"
    [ "$bad" -eq 0 ] || { echo "$bad file(s) damaged" >&2; exit 1; }
    exit 0
fi
docker info >/dev/null 2>&1 || { echo 'Docker is not running; run install-on-unas.sh first' >&2; exit 1; }

# The UniFi OS containers' directories are Btrfs subvolumes without
# copy-on-write (outside pool snapshots); create them before unpacking into them.
list=$(zstd -dc "$B/config.tar.zst" | tar -t)
for c in uckp protect; do
    if grep -q "^$c/" <<< "$list"; then
        [ -e "$A/$c" ] || { btrfs subvolume create "$A/$c" >/dev/null; chattr +C "$A/$c"; }
    fi
done
# configuration and identities; existing files stay as they are
zstd -dc "$B/config.tar.zst" | tar -C "$A" -xp --skip-old-files
echo "configuration restored (existing files kept)"

for f in "$B"/images/*.tar.zst; do
    echo "loading $(basename "$f")"
    zstd -dc "$f" | docker load -q
done

# LoxBerry's volume, if it is new or empty
if [ -f "$B/loxberry-volume.tar.zst" ]; then
    docker volume inspect unas-apps_loxberry >/dev/null 2>&1 || \
        docker volume create --label com.docker.compose.project=unas-apps \
            --label com.docker.compose.volume=loxberry unas-apps_loxberry >/dev/null
    lv=$(docker volume inspect -f '{{.Mountpoint}}' unas-apps_loxberry)
    if [ -z "$(ls -A "$lv")" ]; then
        zstd -dc "$B/loxberry-volume.tar.zst" | tar -C "$lv" -xp
        echo "LoxBerry volume restored"
    else
        echo "LoxBerry volume not empty, left as it is"
    fi
fi

echo
echo "App backups in $B (restore them in UniFi OS if its data is new, docs/RECOVERY.md):"
ls -1t "$B"/unifi-os/*.unifi 2>/dev/null || true   # console with all apps
ls -1t "$B"/network/*.unf 2>/dev/null | head -3 || true
ls -1t "$B"/protect/*.zip 2>/dev/null || true
ls -1t "$B"/homeassistant/*.tar 2>/dev/null || true   # in Home Assistant's onboarding
EOF

[[ "$check" == true ]] && exit 0
cat <<'TXT'

Next:
  extras/unas-apps/uckp/install-uckp.sh <target> --ip <UCKP_IP> --mac <UCKP_MAC> --size <SIZE>
  extras/unas-apps/install-on-unas.sh <target> --up
(identity files and images from the set are kept; see docs/RECOVERY.md)
UniFi OS with new data: restore a console backup (unifi-os/*.unifi) in its
setup wizard, or Network (.unf) and Protect (.zip) one by one afterwards.
TXT
