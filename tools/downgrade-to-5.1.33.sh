#!/bin/bash
# Move a four-bay UNVR from any newer stock UniFi OS (verified: 6.0.11) to the
# signed UNVR 5.1.33 baseline with Ubiquiti's own updater, before conversion.
#
#   tools/downgrade-to-5.1.33.sh <UNVR-IP>
#
# Before running: in Control Plane -> Updates clear Auto-Update for UniFi OS and
# every application, and in Control Plane -> Console enable SSH with a password.
# You are asked for that SSH password once (a ControlMaster is reused after).
# The downgrade keeps settings and does not touch the disks; U-Boot is left
# alone when it already matches 5.1.33 ("uboot matched, skip").
set -Eeuo pipefail
ip=${1:?usage: $0 <UNVR-IP>}
url=https://fw-download.ubnt.com/data/unifi-nvr/976a-UNVR-5.1.33-84c520f3-fb97-41e0-be2b-b0f89c46c7b8.bin
sha=b170e97f9b7a703947380aed1108221e70ab18074b986906aca9df10891ca1e0
target=UNVR4.al324.v5.1.33.44ce47b.260909.0025
sock=$(mktemp -u "${TMPDIR:-/tmp}/unvr-downgrade.XXXXXX")
trap 'ssh -S "$sock" -O exit "root@$ip" >/dev/null 2>&1 || true' EXIT

ssh -M -S "$sock" -fNT -o ControlPersist=900 -o StrictHostKeyChecking=accept-new "root@$ip"
remote() { ssh -S "$sock" "root@$ip" "$@"; }

current=$(remote cat /usr/lib/version)
echo "current firmware: $current"
[[ "$current" == UNVR4.al324.v* ]] || { echo 'not a four-bay UNVR' >&2; exit 1; }
[[ "$current" != "$target" ]] || { echo 'already on UNVR 5.1.33; nothing to do'; exit 0; }
remote "grep -q '^  schedule: null\$' /data/unifi-core/config/firmware.yaml" \
    || { echo 'automatic firmware updates are still enabled; disable them first' >&2; exit 1; }

echo 'downloading UNVR 5.1.33 on the UNVR and checking it with the stock updater'
remote "set -eu
    mkdir -p /mnt/.rwfs/fw-5133 && cd /mnt/.rwfs/fw-5133
    [ -f UNVR-5.1.33.bin ] && [ \"\$(sha256sum UNVR-5.1.33.bin | cut -d' ' -f1)\" = $sha ] || \
        curl -fsSL --proto =https --retry 5 -o UNVR-5.1.33.bin $url
    test \"\$(sha256sum UNVR-5.1.33.bin | cut -d' ' -f1)\" = $sha
    /sbin/ubnt-tools fwupdate -dc UNVR-5.1.33.bin >/dev/null
    test \"\$(fwinfo -k UNVR-5.1.33.bin)\" = $target"
echo 'image verified (SHA-256, Ubiquiti signature, version)'

read -r -p "Flash UNVR 5.1.33 now? The UNVR reboots. [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo 'aborted; nothing was flashed'; exit 1; }
remote "nohup /sbin/ubnt-systool fwupdate /mnt/.rwfs/fw-5133/UNVR-5.1.33.bin > /mnt/.rwfs/fw-5133/fwupdate.log 2>&1 &"
echo 'flashing; waiting for the UNVR to come back (usually 2-3 minutes)'
sleep 60
for _ in $(seq 1 90); do
    nc -z -G 2 "$ip" 22 >/dev/null 2>&1 && break
    sleep 5
done
echo 'SSH is back. Log in once more to confirm:'
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@$ip" 'cat /usr/lib/version'
