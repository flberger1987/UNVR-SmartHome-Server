#!/bin/bash

# One-shot helper that completes storage handoff after UNAS setup and removes
# the temporary SSH access used by the converter.

set -Eeuo pipefail
export LC_ALL=C
umask 077

readonly runtime=/data/unvr-unas-runtime
readonly settings=/data/unifi-core/config/settings.yaml
readonly storage_config=/etc/ustd/storage.conf

log() {
    printf 'unvr-unas-finalizer: %s\n' "$*"
}

sha256() {
    sha256sum "$1" | awk '{print $1}'
}

package_version() {
    dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}

current_ulp_owner() {
    local count owner
    count=$(sudo -u postgres psql -X -d ulp-go -A -t \
        -c 'SELECT count(*) FROM "user" WHERE deleted_at IS NULL' 2>/dev/null || true)
    [[ "$count" == 1 ]] || return 1
    owner=$(sudo -u postgres psql -X -d ulp-go -A -t \
        -c 'SELECT unique_id FROM "user" WHERE deleted_at IS NULL' 2>/dev/null || true)
    [[ -n "$owner" && "$owner" != *[[:space:]]* ]] || return 1
    printf '%s\n' "$owner"
}

write_storage_request_marker() {
    local value=$1 target=$runtime/drive-storage-requested tmp
    case "$value" in
        'v2-pool=raid5 slots=1 hotspare=false'|\
        'storage-setup=existing-drive-ui'|\
        'storage-setup=deferred-to-drive-ui') ;;
        *) return 1 ;;
    esac
    [[ ! -L "$target" ]] || return 1
    tmp=$(mktemp "$runtime/.drive-storage-requested.XXXXXX") || return 1
    trap 'rm -f -- "${tmp:-}"' RETURN EXIT HUP INT TERM
    printf '%s\n' "$value" > "$tmp" || return 1
    chmod 0600 "$tmp" || return 1
    sync "$tmp" || return 1
    mv -f "$tmp" "$target" || return 1
    sync "$target" || return 1
    trap - RETURN EXIT HUP INT TERM
}

validate_fuse_runtime() (
    set -Eeuo pipefail
    local test_root source_dir mount_dir source_hash mounted_hash
    grep -qw fuse /proc/modules || return 1
    [[ -c /dev/fuse && -x /usr/sbin/rclone ]] || return 1
    test_root=$(mktemp -d /run/unvr-fuse-validation.XXXXXX) || return 1
    source_dir=$test_root/source
    mount_dir=$test_root/mount
    mkdir -m 0700 "$source_dir" "$mount_dir" || return 1
    trap 'set +e; mountpoint -q "$mount_dir" && fusermount3 -u "$mount_dir"; rm -rf -- "$test_root"' EXIT HUP INT TERM
    printf 'unvr-fuse-source-probe\n' > "$source_dir/source.txt" || return 1
    source_hash=$(sha256 "$source_dir/source.txt") || return 1
    /usr/sbin/rclone mount "$source_dir" "$mount_dir" \
        --daemon --vfs-cache-mode writes --log-file "$test_root/rclone.log" --log-level INFO || return 1
    for _ in $(seq 1 40); do mountpoint -q "$mount_dir" && break; sleep 0.25; done
    mountpoint -q "$mount_dir" || return 1
    [[ "$(findmnt -rn -o FSTYPE "$mount_dir")" == fuse.rclone ]] || return 1
    [[ "$(sha256 "$mount_dir/source.txt")" == "$source_hash" ]] || return 1
    printf 'unvr-fuse-mounted-write-probe\n' > "$mount_dir/mounted-write.txt" || return 1
    sync "$mount_dir/mounted-write.txt" || return 1
    mounted_hash=$(sha256 "$mount_dir/mounted-write.txt") || return 1
    for _ in $(seq 1 40); do [[ -f "$source_dir/mounted-write.txt" ]] && break; sleep 0.25; done
    [[ "$(sha256 "$source_dir/mounted-write.txt")" == "$mounted_hash" ]] || return 1
    fusermount3 -u "$mount_dir" || return 1
    for _ in $(seq 1 40); do ! mountpoint -q "$mount_dir" && break; sleep 0.25; done
    ! mountpoint -q "$mount_dir"
)

validate_iscsi_contract() {
    local owner response_file status
    owner=$(current_ulp_owner) || return 1
    response_file=$(mktemp /run/unvr-unas-iscsi-contract.XXXXXX) || return 1
    trap 'rm -f -- "${response_file:-}"' RETURN EXIT HUP INT TERM
    status=$(curl -sS --max-time 10 -o "$response_file" -w '%{http_code}' \
        -H "X-UserId: $owner" -H 'X-UserRole: owner' \
        http://127.0.0.1:16080/api/v2/iscsi/luns 2>/dev/null) || return 1
    [[ "$status" == 403 ]] || return 1
    jq -e '.err.code == "ErrForbidden" and .err.msg == "iSCSI functionality is not supported on this system"' \
        "$response_file" >/dev/null 2>&1
}

set_storage_automode() {
    local desired=$1 tmp
    [[ "$desired" == true || "$desired" == false ]] || return 1
    [[ -f "$storage_config" && ! -L "$storage_config" ]] || return 1
    jq -e '
        .max_raid_size == 0 and
        .max_volume_size == 0 and
        .max_num_volume == 1 and
        .prefer_raid == "raid5" and
        .filesystem == ["btrfs"] and
        .hotspare == false and
        .setup == false and
        (.automode | type) == "boolean"
    ' "$storage_config" >/dev/null 2>&1 || return 1
    tmp=$(mktemp /etc/ustd/.storage.conf.unvr-unas.XXXXXX) || return 1
    trap 'rm -f -- "${tmp:-}"' RETURN EXIT HUP INT TERM
    jq --argjson desired "$desired" '.automode = $desired' "$storage_config" > "$tmp" || return 1
    chown --reference="$storage_config" "$tmp" || return 1
    chmod --reference="$storage_config" "$tmp" || return 1
    sync "$tmp" || return 1
    mv -f "$tmp" "$storage_config" || return 1
    sync "$storage_config" || return 1
    trap - RETURN EXIT HUP INT TERM
    jq -e --argjson desired "$desired" '.automode == $desired' "$storage_config" >/dev/null 2>&1 || return 1
    PYTHONPATH="$runtime" timeout 15 python3 - "$desired" <<'PY' || return 1
import sys
import threading
import time
from ustd.statusdb.sdb_client import SDBClient

desired = sys.argv[1] == "true"
client = SDBClient()
threading.Thread(target=client.run, daemon=True).start()
for _ in range(100):
    root = client.get(None, {})
    if isinstance(root, dict) and "system" in root:
        break
    time.sleep(0.1)
else:
    raise SystemExit("live USTD status database is unavailable")
client.update("config.storage.automode", desired)
for _ in range(100):
    current = client.get("config.storage.automode", "<missing>")
    if current is desired:
        break
    time.sleep(0.1)
if current is not desired:
    raise SystemExit("live USTD automode state did not change")
PY
    [[ "$(ustate dump events 2>/dev/null | jq -r '.events.config.storage.automode')" == "$desired" ]]
}

release_storage_service() {
    # The stock UNAS setup page creates its pool through Drive's v2 API.
    # Keep USTD's autonomous initializer disabled until that official request
    # has created both the physical pool and Drive's ownership records.
    set_storage_automode false || return 1
    if [[ -e "$runtime/prestorage-block-usd" ]]; then
        [[ -f "$runtime/prestorage-block-usd" && ! -L "$runtime/prestorage-block-usd" ]] || return 1
        rm -f -- "$runtime/prestorage-block-usd" || return 1
    fi
    systemctl daemon-reload || return 1
    systemctl start unvr-unas-btrfs.service || return 1
    systemctl start usd.service || return 1
    systemctl is-active --quiet usd.service
}

defer_drive_storage_to_user() {
    local prestorage existing
    if [[ -e "$runtime/drive-storage-requested" || -L "$runtime/drive-storage-requested" ]]; then
        [[ -f "$runtime/drive-storage-requested" && ! -L "$runtime/drive-storage-requested" ]] || return 1
        existing=$(cat "$runtime/drive-storage-requested")
        case "$existing" in
            'v2-pool=raid5 slots=1 hotspare=false'|\
            'storage-setup=existing-drive-ui'|\
            'storage-setup=deferred-to-drive-ui') return 0 ;;
            *) return 1 ;;
        esac
    fi
    prestorage=$(cat "$runtime/prestorage-ready" 2>/dev/null || true)
    case "$prestorage" in
        'physical=UNVR-5.1.33 logical=UNASPRO-5.1.33 storage=no-disk state=pre-adoption'|\
        'physical=UNVR-5.1.33 logical=UNASPRO-5.1.33 storage=preserve state=pre-adoption'|\
        'physical=UNVR-5.1.33 logical=UNASPRO-5.1.33 storage=blank state=pre-adoption')
            write_storage_request_marker 'storage-setup=deferred-to-drive-ui'
            return
            ;;
        *) return 1 ;;
    esac
}

console_ready() {
    local system
    grep -q '^isSetup: true$' "$settings" 2>/dev/null || return 1
    systemctl is-active --quiet unifi-core.service || return 1
    system=$(curl -ksSf --max-time 5 https://127.0.0.1/api/system 2>/dev/null) || return 1
    jq -e '
        (.deviceState == "setup" or .deviceState == "updateAvailable") and
        .hardware.shortname == "UNASPRO"
    ' <<<"$system" >/dev/null 2>&1
}

ustd_boot_ready() {
    systemctl is-active --quiet multi-user.target || return 1
    systemctl is-active --quiet sysready.target || return 1
    [[ "$(ustate dump events 2>/dev/null | jq -r '.events.system.bootstage // empty')" == ready ]]
}

storage_ready() {
    local state schema ownership request_mode expected_schema drive_version managed=false
    request_mode=$(cat "$runtime/drive-storage-requested" 2>/dev/null || true)
    for unit in unifi-core unifi-drive usd uhwd ulp-go udcd nginx unvr-unas-btrfs; do
        systemctl is-active --quiet "$unit" || return 1
    done
    case "$request_mode" in
        'v2-pool=raid5 slots=1 hotspare=false'|'storage-setup=existing-drive-ui') managed=true ;;
        'storage-setup=deferred-to-drive-ui') ;;
        *) return 1 ;;
    esac
    [[ "$managed" == false ]] || systemctl is-active --quiet smbd || return 1
    state=$(/usr/bin/node24 "$runtime/query-drive-storage-state" 2>/dev/null) || return 1
    schema=$(sudo -u postgres psql -X -d unifi-drive -A -F '|' -t \
        -c 'SELECT version,dirty FROM schema_migrations' 2>/dev/null || true)
    drive_version=$(package_version unifi-drive)
    case "$drive_version" in
        4.3.10) expected_schema='123|f' ;;
        4.4.9) expected_schema='129|f' ;;
        *) return 1 ;;
    esac
    [[ "$schema" == "$expected_schema" ]] || return 1
    if [[ "$request_mode" == 'storage-setup=deferred-to-drive-ui' ]]; then
        jq -e '
            (.poolsList | type) == "array" and
            (.disksList | type) == "array" and
            (.poolsList | all(.initializationStatus != 1))
        ' <<<"$state" >/dev/null 2>&1
        return
    fi
    [[ "$managed" == true ]] || return 1
    jq -e '
        (.poolsList | any(
            .totalBytes > 0 and
            .initializationStatus == 2 and
            (.status as $status | ([6, 7, 17] | index($status)) != null) and
            (.diskIdsList | length) >= 1
        )) and
        (.disksList | any(.slotId == 1 and .status == 4))
    ' <<<"$state" >/dev/null 2>&1 || return 1
    ownership=$(sudo -u postgres psql -X -d unifi-drive -A -F '|' -t \
        -c 'SELECT (SELECT count(*) FROM storage_pools),(SELECT count(*) FROM shared_drives),(SELECT count(*) FROM storages)' \
        2>/dev/null || true)
    [[ "$ownership" == '1|1|0' ]]
}

verify_update_schedules() {
    python3 - "${1:-/data/unifi-core/config/firmware.yaml}" \
        "${2:-/data/unifi-core/config/apps.userPrefs.yaml}" <<'PY'
import sys
import yaml
with open(sys.argv[1]) as stream:
    firmware = yaml.safe_load(stream)
with open(sys.argv[2]) as stream:
    preferences = yaml.safe_load(stream)
assert isinstance(firmware, dict) and isinstance(preferences, dict)
settings = firmware['autoUpdate']
assert settings['schedule'] is None and settings['includeApplications'] is False
schedules = preferences['updateSchedules']
assert isinstance(schedules, dict) and all(value is None for value in schedules.values())
PY
}

disable_auto_updates() {
    local owner auth token csrf header_file status
    owner=$(current_ulp_owner) || return 1
    auth=$(jq -nc --arg owner "$owner" '{userId:$owner,expiresInSec:120}' \
        | curl -fsS --max-time 5 -H 'Content-Type: application/json' -d @- \
            http://127.0.0.1:11081/api/authToken) || return 1
    token=$(jq -er .token <<<"$auth") || return 1
    csrf=$(jq -er .csrfToken <<<"$auth") || return 1
    header_file=$(mktemp /run/unvr-unas-update-headers.XXXXXX) || return 1
    trap 'rm -f -- "$header_file"' RETURN EXIT HUP INT TERM
    printf 'X-CSRF-Token: %s\nCookie: TOKEN=%s\n' "$csrf" "$token" > "$header_file"
    chmod 0600 "$header_file"
    status=$(curl -ksS --max-time 30 -o /dev/null -w '%{http_code}' -X PATCH \
        -H 'Content-Type: application/json' -H "@$header_file" \
        -d '{"schedules":{"firmware":null,"drive":null},"useApplicationSchedules":true}' \
        https://127.0.0.1/api/system/updates/schedules || true)
    jq -nc --arg token "$token" '{token:$token}' \
        | curl -fsS --max-time 5 -X DELETE -H 'Content-Type: application/json' -d @- \
            http://127.0.0.1:11081/api/authToken >/dev/null 2>&1 || true
    token=''
    csrf=''
    auth=''
    rm -f -- "$header_file"
    trap - RETURN EXIT HUP INT TERM
    case "$status" in
        200|204) ;;
        *) log "update-schedule API returned HTTP $status"; return 1 ;;
    esac
    verify_update_schedules || { log 'automatic update schedule readback failed'; return 1; }
    log 'disabled automatic console and application updates'
}

finalize_readoption() {
    local completed=$runtime/completed-update tmp storage_mode request_mode
    # Explicit Drive UI pool requests work with automode off. Never let the
    # autonomous initializer consume blank drives after we relinquish setup.
    set_storage_automode false || { log 'failed to preserve user-controlled storage setup'; return 1; }
    validate_fuse_runtime || { log 'FUSE validation failed during finalization'; return 1; }
    validate_iscsi_contract || { log 'UNAS Pro iSCSI contract validation failed'; return 1; }
    disable_auto_updates || { log 'failed to disable automatic updates'; return 1; }
    request_mode=$(cat "$runtime/drive-storage-requested" 2>/dev/null || true)
    case "$request_mode" in
        'v2-pool=raid5 slots=1 hotspare=false'|'storage-setup=existing-drive-ui') storage_mode=managed ;;
        'storage-setup=deferred-to-drive-ui') storage_mode=deferred ;;
        *) return 1 ;;
    esac
    tmp=$(mktemp "$runtime/.storage-mode.XXXXXX") || return 1
    printf '%s\n' "$storage_mode" > "$tmp" || return 1
    chmod 0600 "$tmp" || return 1
    mv -f "$tmp" "$runtime/storage-mode" || return 1
    tmp=$(mktemp "$runtime/.completed-update.XXXXXX") || return 1
    printf '%s\n' 'physical=UNVR-5.1.33 logical=UNASPRO-5.1.33 state=complete' > "$tmp" || return 1
    chmod 0600 "$tmp" || return 1
    mv -f "$tmp" "$completed" || return 1
    systemctl enable unvr-unas-drive-restore.service >/dev/null || return 1
    if ! "$runtime/guarded-fwupdate" --profile-check >/dev/null; then
        log 'guarded final profile validation failed'
        rm -f -- "$completed"
        rm -f -- "$runtime/storage-mode"
        systemctl disable unvr-unas-drive-restore.service >/dev/null 2>&1 || true
        return 1
    fi
    if ! disable_temporary_ssh; then
        log 'failed to rotate and disable temporary SSH access'
        rm -f -- "$completed"
        rm -f -- "$runtime/storage-mode"
        systemctl disable unvr-unas-drive-restore.service >/dev/null 2>&1 || true
        return 1
    fi
    rm -f -- "$runtime/prestorage-ready" || return 1
    mv -f "$runtime/pending-logical-readoption" "$runtime/completed-logical-readoption" || return 1
    systemctl disable unvr-unas-readopt-ssh.service >/dev/null 2>&1 || true
    log 'official UNAS setup handoff finalized successfully'
}

disable_temporary_ssh() {
    local owner auth token csrf rotate_status disable_status header_file replacement
    owner=$(current_ulp_owner) || return 1
    auth=$(jq -nc --arg owner "$owner" '{userId:$owner,expiresInSec:120}' \
        | curl -fsS --max-time 5 -H 'Content-Type: application/json' -d @- \
            http://127.0.0.1:11081/api/authToken) || return 1
    token=$(jq -er .token <<<"$auth") || return 1
    csrf=$(jq -er .csrfToken <<<"$auth") || return 1
    header_file=$(mktemp /run/unvr-unas-auth-headers.XXXXXX) || return 1
    trap 'rm -f -- "$header_file"' RETURN EXIT HUP INT TERM
    printf 'X-CSRF-Token: %s\nCookie: TOKEN=%s\n' "$csrf" "$token" > "$header_file"
    chmod 0600 "$header_file"
    replacement="DisabledA1$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
    rotate_status=$(jq -nc --arg password "$replacement" '{password:$password}' \
        | curl -ksS --max-time 30 -o /dev/null -w '%{http_code}' -X POST \
            -H 'Content-Type: application/json' \
            -H "@$header_file" \
            -d @- https://127.0.0.1/api/system/ssh/setpassword || true)
    replacement=
    disable_status=$(curl -ksS --max-time 30 -o /dev/null -w '%{http_code}' -X PATCH \
        -H 'Content-Type: application/json' \
        -H "@$header_file" \
        -d '{"ssh":{"enabled":false}}' https://127.0.0.1/api/system || true)
    jq -nc --arg token "$token" '{token:$token}' \
        | curl -fsS --max-time 5 -X DELETE -H 'Content-Type: application/json' -d @- \
            http://127.0.0.1:11081/api/authToken >/dev/null 2>&1 || true
    token=''
    csrf=''
    auth=''
    rm -f -- "$header_file"
    trap - RETURN EXIT HUP INT TERM
    case "$rotate_status" in 200|201|202|204) ;; *) return 1 ;; esac
    case "$disable_status" in
        200|201|202|204) ;;
        *) log "SSH disable API returned HTTP $disable_status; applying the stock local fallback" ;;
    esac
    if systemctl is-active --quiet ssh.service; then
        /sbin/ubnt-systool sshd false >/dev/null 2>&1 || return 1
    fi
    for _ in $(seq 1 60); do
        if ! systemctl is-active --quiet ssh.service && [[ "$(ubnt-systool sshd 2>/dev/null || true)" == disabled ]]; then
            log 'rotated the temporary SSH password and disabled SSH access'
            return 0
        fi
        sleep 1
    done
    return 1
}

[[ -f $runtime/pending-logical-readoption ]] || exit 0
log 'waiting for official UNAS setup handoff readiness'
for _ in $(seq 1 1200); do
    if console_ready && ustd_boot_ready; then
        release_storage_service || { log 'failed to release the guarded storage service'; exit 1; }
        defer_drive_storage_to_user || { log 'failed to defer storage setup to the Drive UI'; exit 1; }
        printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$runtime/readoption-storage-released"
        log 'official UNAS setup is ready for storage finalization'
        break
    fi
    sleep 2
done

[[ -f "$runtime/readoption-storage-released" ]] || {
    printf 'readoption did not complete before storage-release timeout\n' >&2
    exit 1
}

for _ in $(seq 1 1200); do
    if storage_ready && finalize_readoption; then
        exit 0
    fi
    sleep 2
done

printf 'Drive storage did not complete before conversion finalization timeout\n' >&2
exit 1
