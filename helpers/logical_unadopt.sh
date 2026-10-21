#!/bin/bash

# Conversion-preserving alternative to UniFi's reset2defaults flow. The stock
# reset formats the UNVR's internal data, log, and overlay partitions even when
# external storage formatting is disabled. This flow unregisters only Core's
# cloud identity and changes only Core's setup flag. The SATA pool is untouched.

set -Eeuo pipefail
export LC_ALL=C
umask 077

readonly runtime=/data/unvr-unas-runtime
readonly settings=/data/unifi-core/config/settings.yaml
readonly pending=$runtime/pending-logical-readoption
readonly ssh_restorer=$runtime/readopt-ssh-restorer
readonly expected_complete='physical=UNVR-5.1.33 logical=UNASPRO-5.1.33 state=complete'

die() { printf 'logical-unadopt: %s\n' "$*" >&2; exit 1; }

prestorage_state() {
    local marker
    marker=$(cat "$runtime/prestorage-ready" 2>/dev/null || true)
    case "$marker" in
        'physical=UNVR-5.1.33 logical=UNASPRO-5.1.33 storage=blank state=pre-adoption') printf 'blank\n' ;;
        'physical=UNVR-5.1.33 logical=UNASPRO-5.1.33 storage=no-disk state=pre-adoption') printf 'no-disk\n' ;;
        'physical=UNVR-5.1.33 logical=UNASPRO-5.1.33 storage=preserve state=pre-adoption') printf 'preserve\n' ;;
        *) return 1 ;;
    esac
}

verify_blank_slot1() {
    local signature_types partition_count
    [[ ! -e /dev/md3 ]] || die 'storage was initialized before UNAS adoption'
    [[ $(lsblk -nrpo NAME /dev/sda | wc -l) -eq 1 ]] || die 'slot-1 disk is no longer blank'
    signature_types=$(wipefs -n --noheadings --output TYPE /dev/sda 2>/dev/null \
        | sed '/^[[:space:]]*$/d;s/^[[:space:]]*//;s/[[:space:]]*$//' \
        | LC_ALL=C sort -u | paste -sd, -)
    if [[ -n "$signature_types" ]]; then
        [[ "$signature_types" == PMBR,gpt ]] || die 'slot-1 disk gained a non-GPT storage signature'
        partition_count=$(parted -sm /dev/sda unit s print 2>/dev/null \
            | awk -F: '$1 ~ /^[0-9]+$/ {count++} END {print count+0}')
        [[ "$partition_count" == 0 ]] || die 'slot-1 GPT gained a partition'
    fi
}

verify_final() {
    local storage_state
    [[ $(id -u) -eq 0 ]] || die 'root is required'
    [[ -x $runtime/guarded-fwupdate ]] || die 'final guard is missing'
    [[ -x $ssh_restorer ]] || die 'SSH restorer is missing'
    if [[ $(cat "$runtime/completed-update" 2>/dev/null || true) == "$expected_complete" ]]; then
        "$runtime/guarded-fwupdate" --profile-check >/dev/null
        return
    fi
    storage_state=$(prestorage_state) || die 'neither final nor pre-storage conversion marker is valid'
    [[ $(dpkg-query -W -f='${Version}' unifi-core 2>/dev/null) == 5.1.132 ]] \
        || die 'Core version is not the validated pre-storage version'
    case $(dpkg-query -W -f='${Version}' unifi-drive 2>/dev/null || true) in
        4.3.10|4.4.9) ;;
        *) die 'Drive version is not compatibility-profiled for logical unadoption' ;;
    esac
    [[ $(sha256sum /usr/share/unifi-core/app/service.js | awk '{print $1}') == \
        a65c0736fd0abad3df5cc4cd1a42549cacc84e1b76f07ff30eff5cd1d75a774b ]] \
        || die 'logical UNAS Core identity is not active'
    case "$storage_state" in
        blank) verify_blank_slot1 ;;
        no-disk)
            [[ ! -b /dev/sda && ! -b /dev/sdb && ! -b /dev/sdc && ! -b /dev/sdd ]] \
                || die 'a drive was inserted after no-drive conversion validation'
            ;;
        preserve) ;;
    esac
    [[ -f $runtime/prestorage-block-usd ]] || die 'pre-storage USD guard is missing'
    ! systemctl is-active --quiet usd.service || die 'usd is active before UNAS adoption'
}

verify_resume() {
    local storage_state
    [[ $(id -u) -eq 0 ]] || die 'root is required'
    if [[ $(cat "$runtime/completed-update" 2>/dev/null || true) != "$expected_complete" ]]; then
        storage_state=$(prestorage_state) || die 'conversion marker is missing during readoption'
    fi
    [[ $(dpkg-query -W -f='${Version}' unifi-core 2>/dev/null) == 5.1.132 ]] \
        || die 'Core version changed during readoption'
    case $(dpkg-query -W -f='${Version}' unifi-drive 2>/dev/null || true) in
        4.3.10|4.4.9) ;;
        *) die 'Drive version changed to an unprofiled release during readoption' ;;
    esac
    [[ $(sha256sum /usr/share/unifi-core/app/service.js | awk '{print $1}') == \
        a65c0736fd0abad3df5cc4cd1a42549cacc84e1b76f07ff30eff5cd1d75a774b ]] \
        || die 'logical UNAS Core identity changed during readoption'
    if storage_state=$(prestorage_state); then
        case "$storage_state" in
            blank) verify_blank_slot1 ;;
            no-disk)
                [[ ! -b /dev/sda && ! -b /dev/sdb && ! -b /dev/sdc && ! -b /dev/sdd ]] \
                    || die 'a drive was inserted during no-drive readoption'
                ;;
            preserve) ;;
        esac
        [[ -f $runtime/prestorage-block-usd ]] || die 'pre-storage USD guard changed during readoption'
        ! systemctl is-active --quiet usd.service || die 'usd started during pre-storage readoption'
    else
        curl -fsS http://127.0.0.1:16080/api/v2/storage \
            | jq -e '(.pools | any(.capacity > 0 and .initializingStatus == "successful")) and
                     (.disks | any(.slotId == "1" and .state == "optimal"))' >/dev/null \
            || die 'Drive storage changed during readoption'
    fi
}

backup_state() {
    local snapshot db pending_tmp available
    available=$(df -B1 --output=avail "$runtime" | tail -n1 | tr -d ' ')
    [[ "$available" =~ ^[0-9]+$ && "$available" -ge 1073741824 ]] \
        || die 'insufficient free space for the readoption rollback backup'
    snapshot=$runtime/adoption-backups/readoption-$(date -u +%Y%m%dT%H%M%SZ)
    [[ ! -e "$snapshot" ]] || die 'readoption backup timestamp collision'
    install -d -m 0700 "$snapshot" "$snapshot/core-config"
    install -d -m 0700 "$snapshot/databases"
    cp -a /data/unifi-core/config/. "$snapshot/core-config/"
    for db in unifi-core ulp-go uid unifi-directory unifi-drive; do
        sudo -u postgres sh -c 'cd /tmp && exec pg_dump -Fc "$1"' sh "$db" \
            | tee "$snapshot/databases/$db.dump" >/dev/null
        chmod 0600 "$snapshot/databases/$db.dump"
        pg_restore -l "$snapshot/databases/$db.dump" >/dev/null
    done
    chown -R root:root "$snapshot"
    (
        cd "$snapshot"
        find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
        sha256sum -c SHA256SUMS >/dev/null
    )
    pending_tmp=$(mktemp "$runtime/.pending-logical-readoption.XXXXXX")
    printf '%s\n' "$snapshot" > "$pending_tmp"
    chmod 0600 "$pending_tmp"
    mv -f "$pending_tmp" "$pending"
}

ensure_backup() {
    local snapshot
    [[ ! -L $pending ]] || die 'recorded readoption backup pointer is unsafe'
    if [[ ! -e $pending ]]; then
        backup_state
        return
    fi
    [[ -f $pending && ! -L $pending ]] || die 'recorded readoption backup pointer is unsafe'
    snapshot=$(cat "$pending")
    [[ "$snapshot" =~ ^/data/unvr-unas-runtime/adoption-backups/readoption-[0-9]{8}T[0-9]{6}Z$ ]] \
        || die 'recorded readoption backup path is malformed'
    [[ -d $snapshot && -f $snapshot/SHA256SUMS ]] || die 'recorded readoption backup is incomplete'
    (cd "$snapshot" && sha256sum -c SHA256SUMS >/dev/null) || die 'recorded readoption backup failed validation'
}

unregister_cloud() {
    local owner auth token csrf status header_file
    if curl -ksSf https://127.0.0.1/api/system 2>/dev/null \
        | jq -e '.cloudConnected == false and .remoteAccessEnabled == false' >/dev/null; then
        return
    fi
    owner=$(sudo -u postgres psql -X -d ulp-go -A -t \
        -c 'SELECT unique_id FROM "user" WHERE deleted_at IS NULL LIMIT 1')
    [[ -n $owner ]] || die 'current ULP owner is unavailable'
    auth=$(jq -nc --arg owner "$owner" '{userId:$owner,expiresInSec:120}' \
        | curl -fsS --max-time 5 -H 'Content-Type: application/json' -d @- \
            http://127.0.0.1:11081/api/authToken)
    token=$(jq -er .token <<<"$auth")
    csrf=$(jq -er .csrfToken <<<"$auth")
    header_file=$(mktemp /run/unvr-unas-auth-headers.XXXXXX)
    trap 'rm -f -- "$header_file"' RETURN EXIT HUP INT TERM
    printf 'X-CSRF-Token: %s\nCookie: TOKEN=%s\n' "$csrf" "$token" > "$header_file"
    chmod 0600 "$header_file"
    status=$(curl -ksS --max-time 45 -o /dev/null -w '%{http_code}' \
        -H 'Content-Type: application/json' \
        -H "@$header_file" \
        -d '{}' https://127.0.0.1/api/cloud/unregister || true)
    jq -nc --arg token "$token" '{token:$token}' \
        | curl -fsS --max-time 5 -X DELETE -H 'Content-Type: application/json' -d @- \
            http://127.0.0.1:11081/api/authToken >/dev/null 2>&1 || true
    token=''
    csrf=''
    auth=''
    rm -f -- "$header_file"
    trap - RETURN EXIT HUP INT TERM
    [[ $status == 204 ]] || die "Core cloud unregister returned HTTP $status"
}

reset_ulp_owner() {
    local users
    users=$(sudo -u postgres psql -X -d ulp-go -A -t -c 'SELECT count(*) FROM "user"' 2>/dev/null || true)
    if [[ $users == 0 ]]; then
        return
    fi
    [[ $users =~ ^[0-9]+$ ]] || die 'ULP owner state is unavailable'
    /usr/bin/ulp reset
    for _ in $(seq 1 60); do
        if systemctl is-active --quiet ulp-go.service; then
            users=$(sudo -u postgres psql -X -d ulp-go -A -t -c 'SELECT count(*) FROM "user"' 2>/dev/null || true)
            [[ $users == 0 ]] && return
        fi
        sleep 2
    done
    die 'ULP did not reach an unowned state'
}

set_unsetup() (
    local temp=$settings.unvr-unas-new true_count false_count unvr_count unas_count
    [[ -f "$settings" && ! -L "$settings" ]] || die 'Core settings file is missing or unsafe'
    true_count=$(grep -c '^isSetup: true$' "$settings" || true)
    false_count=$(grep -c '^isSetup: false$' "$settings" || true)
    unvr_count=$(grep -c '^name: UNVR$' "$settings" || true)
    unas_count=$(grep -c '^name: UNAS Pro$' "$settings" || true)
    if [[ "$false_count" -eq 1 && "$unas_count" -eq 1 && "$true_count" -eq 0 && "$unvr_count" -eq 0 ]]; then
        systemctl start unifi-core.service
    elif [[ "$true_count" -eq 1 && "$unvr_count" -eq 1 && "$false_count" -eq 0 && "$unas_count" -eq 0 ]]; then
        rm -f -- "$temp"
        sed -e 's/^isSetup: true$/isSetup: false/' -e 's/^name: UNVR$/name: UNAS Pro/' "$settings" > "$temp"
        [[ $(grep -c '^isSetup: false$' "$temp") -eq 1 ]] || die 'failed to create unsetup Core state'
        [[ $(grep -c '^name: UNAS Pro$' "$temp") -eq 1 ]] || die 'failed to create the UNAS Pro setup name'
        chown --reference="$settings" "$temp"
        chmod --reference="$settings" "$temp"
        systemctl stop unifi-core.service
        trap 'systemctl start unifi-core.service >/dev/null 2>&1 || true; rm -f -- "$temp"' EXIT HUP INT TERM
        mv -f "$temp" "$settings"
        systemctl start unifi-core.service
    else
        die 'Core setup state is not a recognized resumable transition'
    fi
    for _ in $(seq 1 90); do
        if curl -ksSf https://127.0.0.1/api/system 2>/dev/null \
            | jq -e '.isSetup == false and .name == "UNAS Pro" and .hardware.shortname == "UNASPRO"' >/dev/null; then
            return
        fi
        sleep 2
    done
    die 'Core did not enter logical UNAS setup mode'
)

enter() {
    local storage_state
    if [[ -f $pending ]]; then
        verify_resume
    else
        verify_final
    fi
    ensure_backup
    unregister_cloud
    reset_ulp_owner
    set_unsetup
    systemctl enable unvr-unas-readopt-ssh.service >/dev/null
    systemctl start --no-block unvr-unas-readopt-ssh.service
    systemctl is-active --quiet unifi-drive.service || die 'Drive stopped during logical unadoption'
    storage_state=$(prestorage_state 2>/dev/null || printf preserved)
    printf 'LOGICAL_UNADOPT_OK platform=UNASPRO firmware=5.1.33 storage=%s\n' "$storage_state"
}

restore_local_setup() {
    [[ -f $pending && ! -L $pending ]] || die 'no safe logical readoption backup is recorded'
    local snapshot
    snapshot=$(cat "$pending")
    [[ "$snapshot" =~ ^/data/unvr-unas-runtime/adoption-backups/readoption-[0-9]{8}T[0-9]{6}Z$ ]] \
        || die 'recorded Core backup path is malformed'
    [[ -d $snapshot/core-config ]] || die 'recorded Core backup is missing'
    (cd "$snapshot" && sha256sum -c SHA256SUMS >/dev/null) || die 'Core backup hash validation failed'
    systemctl stop unifi-core.service
    cp -a "$snapshot/core-config/settings.yaml" "$settings"
    systemctl start unifi-core.service
    for _ in $(seq 1 90); do
        if curl -ksSf https://127.0.0.1/api/system 2>/dev/null \
            | jq -e 'has("isSetup") | not' >/dev/null; then
            printf 'LOGICAL_UNADOPT_LOCAL_RESTORE_OK cloud_readoption_still_required=true\n'
            return
        fi
        sleep 2
    done
    die 'Core did not restore local setup state'
}

case ${1:-} in
    enter) enter ;;
    restore-local) restore_local_setup ;;
    status)
        if [[ -f $pending ]]; then
            printf 'logical-readoption=pending\n'
        else
            printf 'logical-readoption=inactive\n'
        fi
        ;;
    *) die 'usage: logical-unadopt {enter|restore-local|status}' ;;
esac
