#!/bin/bash

# Fixed-release boot validation. OS updates are blocked; this service never
# reinstalls applications, creates storage, or applies firmware.
set -Eeuo pipefail
export LC_ALL=C
umask 077
readonly runtime=/data/unvr-unas-runtime
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
fail() { log "REFUSED: $*"; exit 1; }

wait_for_boot_ready() {
    local attempt
    for (( attempt=1; attempt<=300; attempt++ )); do
        if systemctl is-active --quiet multi-user.target &&
           systemctl is-active --quiet sysready.target &&
           [[ "$(ustate dump events 2>/dev/null | jq -r '.events.system.bootstage // empty')" == ready ]]; then
            return 0
        fi
        sleep 2
    done
    return 1
}

[[ $# == 0 ]] || fail "OS update restoration is not supported by this fixed release"
[[ "$(cat /usr/lib/version)" == UNVR4.al324.v5.1.33.44ce47b.260909.0025 ]] \
    || fail "physical firmware is not the pinned UNVR 5.1.33 baseline"
[[ "$(cat "$runtime/completed-update" 2>/dev/null || true)" == \
    'physical=UNVR-5.1.33 logical=UNASPRO-5.1.33 state=complete' && ! -e "$runtime/pending-update" ]] \
    || fail "the fixed UNAS profile has not completed setup"
storage_mode=$(cat "$runtime/storage-mode" 2>/dev/null || true)
case "$storage_mode" in managed|deferred) ;; *) fail "storage mode is missing or invalid" ;; esac
wait_for_boot_ready || fail "system did not reach the authoritative boot-ready state"
ready=false
for (( attempt=1; attempt<=180; attempt++ )); do
    ready=true
    for unit in unifi-core unifi-drive usd uhwd ulp-go udcd nginx wsdd-server unvr-unas-btrfs; do
        systemctl is-active --quiet "$unit" || ready=false
    done
    if [[ "$storage_mode" == managed ]]; then
        systemctl is-active --quiet smbd || ready=false
        findmnt -rn -t btrfs -o TARGET 2>/dev/null | grep -qE '^/volume/' || ready=false
    fi
    if ! curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:16080/api/v2/storage \
        | jq -e '(.pools | type) == "array" and (.disks | type) == "array"' >/dev/null 2>&1; then
        ready=false
    fi
    [[ "$ready" == true ]] && break
    sleep 2
done
[[ "$ready" == true ]] || fail "UNAS services did not become ready after reboot"
"$runtime/guarded-fwupdate" --profile-check >/dev/null \
    || fail "pinned UNAS profile failed reboot validation"
log "pinned UNAS Pro 5.1.33 profile remains healthy after reboot"
