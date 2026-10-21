#!/bin/bash
# Guarded macOS orchestrator for the pinned UNVR 5.1.33 -> UNAS Pro 5.1.33 setup.

if [[ -z "${UNVR_UNAS_EXECUTION_SNAPSHOT_DIR:-}" ]]; then
    snapshot_dir=$(mktemp -d /private/tmp/unvr-unas-exec.XXXXXX) || exit 1
    snapshot="$snapshot_dir/convert.sh"
    snapshot_ready=false
    for _ in 1 2 3; do
        source_hash_before=$(shasum -a 256 "$0" 2>/dev/null | awk '{print $1}') || break
        install -m 0700 "$0" "$snapshot" || break
        source_hash_after=$(shasum -a 256 "$0" 2>/dev/null | awk '{print $1}') || break
        snapshot_hash=$(shasum -a 256 "$snapshot" 2>/dev/null | awk '{print $1}') || break
        if [[ "$source_hash_before" == "$source_hash_after" &&
              "$source_hash_after" == "$snapshot_hash" ]]; then
            snapshot_ready=true
            break
        fi
    done
    if [[ "$snapshot_ready" != true ]]; then
        rm -rf -- "$snapshot_dir"
        printf 'Unable to capture a stable converter snapshot; rerun the command.\n' >&2
        exit 1
    fi
    exec env UNVR_UNAS_EXECUTION_SNAPSHOT_DIR="$snapshot_dir" "$snapshot" "$@"
fi

set -Eeuo pipefail
export LC_ALL=C
export COPYFILE_DISABLE=1
umask 077

readonly REMOTE_ENGINE_SHA256=65fac4639a5e8e42c86ed1e2ca34022f2440b1316f86321d113889940dcd2112
readonly UPDATE_PROFILE_BUILDER_SHA256=eafdbca2b7d40e4bd67a44581e9d32132cfc548221d7aaccd7e1007b6aed10a4
readonly DEBIAN_DRIVE_CLOSURE_SHA256=52e38d9730228dc2e6632cccbcd777498450d2b79f0ebf1077fa34dec8d197f9
readonly DEBIAN_KBUILD_CLOSURE_SHA256=fb99e5bfe01f99d9f40f613e7610ec34c77a1c67c0264f74b26cc455487471f8
readonly PAYLOAD_CONTRACT_SHA256=483b83cd8e3e72c07ecbe5d81c2472cb50daa890da9f341e55f096835f765ce8
readonly UBIQUITI_DRIVE_PACKAGES_SHA256=8fdfe83b30b934cc5b00b21a9a9ec812901ac979ffd65b9985b0fd012bf31067
readonly CORE_IDENTITY_BUILDER_SHA256=806eab270b38060622a754bb0ffcf1fcb648d6b85bbfaf94cd1498ce5ab931ae
readonly CORE_5X_BUILDER_SHA256=472ab10f713242d2218069b1717b2c45ee75abce434b6ac6db51c649293895d4
readonly IDENTITY_OVERLAY_BUILDER_SHA256=c00fb9a5073d6f4c9c4a67903766cd97d0a789e628da49853eca7c191c89a84f
readonly PORTAL_BUILDER_SHA256=8554cbb7f31afd281466930a492c51a33ae1820d9b981aabb3adcaa0abb8625a
readonly STORAGE_UI_VERIFIER_SHA256=20014943e53248798094a8db40f9c84f6825db3100f4d2c561448f4890524427
readonly WSDD5_BUILDER_SHA256=e429f916120390c305a667214e384fe02cf0dc516ac7847b4135976f79e666c2
readonly DRIVE_STORAGE_QUERY_SHA256=dd90cb4319ae43fb15a1c3c5635f540c0cb4f138e0741c08fcab7ebc62a156c9
readonly IDENTITY_RESTORE_SHA256=4b5ae523ef7a73c78cff99c7584b4871f9f84fe88c51d4dfa1b8243d84b8782a
readonly DRIVE_RESTORE_SHA256=255c853f34d60b8ea142b7131c18a2e074fd6a7f00f89e43ff7d754c05a14647
readonly DRIVE_LAUNCHER_SHA256=28197a0032fbad95329dd5e9d4ca1f17adc5334f38561a8229ff8c5cbb9c0af3
readonly DRIVE_IDENTITY_ADAPTER_SHA256=702081e0478f2cbdd0147caef1f0c21ce8600691b2c2d9c9910626cd555759a4
readonly IDENTITY_UNIT_SHA256=11471cd6329c8482803e54a1f5a0cbbc0d972a690103fe68f4e39f29d0b5854d
readonly DRIVE_UNIT_SHA256=30e351f068f49559770c692540ec9198a729d7f131b50d00e2dc2b2345920ec6
readonly GUARDED_FWUPDATE_SHA256=73cc8f8042e322d156b4e4078aa15b508cc6519e03c835d80987b6200c9df6fb
readonly LOGICAL_UNADOPT_SHA256=65149af2ff8b52acc260f22cf72343b506274873ea6137dc991903199155524d
readonly READOPT_SSH_RESTORER_SHA256=e8ab54e705a072ddd40c09f82679fadcc7dfcdb03fccd091a5166be62f73e6d1
readonly READOPT_SSH_UNIT_SHA256=f71cf3e3839d74606989e1ba278cdd52ba37466eb662aa24f06a3775025a7977
readonly EMBEDDED_HELPERS_SHA256=2a1f9bc556205c0b72319f7e5a52dee38bff76fabfa4f968fbf6aaed5ad1f452
readonly TEMPORARY_SSH_PASSWORD=UnvrToUnasConversion1

script_dir=
remote_engine=
profile_builder=

command=install
unvr_ip=
controller_ip=
controller_site=
controller_client_mac=
controller_cleanup_mode=unresolved
skip_controller_cleanup=false
prebuilt_modules=
artifact_cache=
unas_firmware=
unvr5_firmware=
unas5_firmware=
dry_run=false
temp_root=
execution_snapshot_dir=${UNVR_UNAS_EXECUTION_SNAPSHOT_DIR:-}
control_socket=
ssh_password=$TEMPORARY_SSH_PASSWORD
known_hosts=
api_cookie=
api_response=
api_headers=
api_csrf=
api_csrf_header=
controller_api_cookie=
controller_api_response=
controller_api_headers=
controller_api_csrf=
controller_api_csrf_header=
ui_account=
ui_account_password=
mfa_token=
spinner_pid=
spinner_label=
interrupt_prompt_active=false
interrupt_declined=false
interrupt_reenable_errexit=false
timeline_active=false
timeline_label=
timeline_sequence_started=-1
timeline_last_number=0
timeline_last_total=0
timeline_header_rewrite_safe=false
timeline_current_number=0
timeline_current_total=0
timeline_percentage_tenths=0
timeline_step_base_tenths=0
timeline_step_ceiling_tenths=0
timeline_action_index=0
timeline_action_budget=1
timeline_time_left=
temporary_update_ssh_configured=false
timeline_eta_anchor_seconds=0
timeline_eta_anchor_remaining=0
timeline_dashboard_drawn=false
timeline_dashboard_rows=12
timeline_step_titles=(
    'Create temporary UNVR ownership and secure SSH access'
    'Verify signed UNVR 5.1.33 baseline and storage-preservation state'
    'Build the hash-verified official UNAS compatibility payload'
    'Capture rollback state and install safety guards'
    'Build exact native Btrfs, Zstd and FUSE modules'
    'Install scoped UNAS Pro identity and official Drive userspace'
    'Verify UNAS services while preserving installed storage'
    'Reboot and run pre-storage health validation'
    'Complete official UNAS setup and verify the handoff'
)
captured_output=
askpass_writer_pid=
setup_checkpoint_rows=0

usage() {
    cat <<'EOF'
Usage:
  convert.sh [install] [--ip IPv4] [--controller-ip IPv4 | --skip-controller-cleanup] [firmware options] [--dry-run]
  convert.sh setup-only [--ip IPv4]
  convert.sh status [--ip IPv4]
  convert.sh disarm [--ip IPv4]
  convert.sh rollback [--ip IPv4]
  convert.sh unadopt [--ip IPv4]

Runs only from macOS and operates on an unmodified four-bay UNVR. Exact UniFi
OS 5.1.33 is the deterministic conversion baseline. A different stock UNVR
version is first normalized to the pinned, signed official 5.1.33 image when
the source updater, hardware, and signed-firmware gates all pass.

install begins with a normal yes/no destructive confirmation, invokes
Ubiquiti's stock factory reset with external-storage formatting, waits for the
unconfigured UNVR to return, and then starts conversion. This permanently
erases the console configuration and ALL data on every installed SATA drive.
It also unregisters only this UNVR console from Site Manager and forgets its
stale offline client record from the original UniFi Network controller. Site
Manager may retain the now-empty site shell until Ubiquiti permits its removal;
that shell can instead be reused when adopting the converted UNAS. The Network
site itself and every other client remain untouched. The controller is detected
from the UNVR gateway; --controller-ip overrides that address when necessary.
--skip-controller-cleanup skips controller discovery and the stale-client
cleanup entirely, for networks without a UniFi OS console running Network.
Declining the confirmation exits without resetting or converting the console.

Authentication and privacy:
  - UI Account credentials and MFA automate normal UniFi sign-in, temporary
    console ownership, local setup, Site Manager unregistration, temporary SSH,
    automatic-update control, and exact-client cleanup when the original Network
    site is accessible.
  - The password and MFA code are held only in process memory, never written to
    disk or logs, never placed in command arguments, and cleared on exit.
  - They are sent only over HTTPS to local UniFi console/controller services and
    the Ubiquiti UI identity services used by the normal sign-in flow.
  - Private temporary session cookies and CSRF material are permission-restricted
    and deleted when the script exits.

Warranty and liability:
  - This is an unofficial community conversion and is not supported by Ubiquiti.
  - It will probably void any applicable Ubiquiti warranty.
  - The author is not liable for data loss, hardware damage, loss of service, or
    any other damages resulting from use of this script.

The installer assigns the temporary SSH password `UnvrToUnasConversion1`
through the local UniFi API and never asks the user for an SSH password. SSH is
used only for conversion and is disabled by the on-device finalizer after UNAS
setup completes.

setup-only performs only that temporary console ownership, SSH and update-
schedule configuration, then exits before firmware normalization or conversion.

Optional exact official image overrides for install:
  --unvr-5-firmware FILE     UNVR 5.1.33
  --unas-5-firmware FILE     UNAS Pro 5.1.33

Optional local caches for install (see tools/run-conversion.sh):
  --artifact-cache DIR       reuse hash-pinned Debian downloads laid out like
                             the builder's output directory
  --prebuilt-modules DIR     zstd_compress.ko, btrfs.ko and fuse.ko built with
                             tools/build-modules.sh; staged on the UNVR so the
                             modules phase verifies them instead of compiling

install downloads (or accepts) exact official Ubiquiti firmware, extracts only
profiled userspace as data, installs Drive, builds native Btrfs/FUSE modules,
applies the scoped UNAS identity and blocks subsequent OS firmware updates. The
repository does not need to contain any firmware binaries: missing images are
downloaded directly from Ubiquiti and accepted only after exact size and
SHA-256 validation. Downloads remain private temporary files and are removed
when the installer exits. A source already on 5.1.33 performs no firmware
write. Other eligible stock UNVR versions are normalized through the console's
own signed updater, rebooted and exact-hash checked before conversion.
The direct 5.1.33 path supports zero to four installed drives. After the
confirmed reset, storage-pool creation is left to the user in the official
Drive UI. The installer validates a reboot, unregisters temporary ownership,
and asks you to complete official UNAS Pro setup in the web UI or mobile app.
Press Enter when finished. The installer checks the console's local setup
status and prompts again if setup is incomplete or cannot be verified.

rollback restores guarded software/configuration state. It deliberately does
not erase or restore the SATA storage pool or user data.

This release installs the fixed UNAS Pro 5.1.33 baseline. Automatic OS and
application updates are disabled. Control Plane OS firmware installations and
legacy prepare-os-update/arm commands are not supported. Manual Drive updates
remain subject to their existing compatibility checks; no arbitrary future
OS or Drive release is implied to be supported.

--dry-run performs exact read-only target and storage-inventory gates. It downloads,
installs, patches, stops, formats, reboots, or persists nothing.
EOF
}

spinner_clear() {
    local had_errexit=false
    [[ $- == *e* ]] && had_errexit=true
    set +e
    if [[ -n "$spinner_pid" ]]; then
        kill "$spinner_pid" >/dev/null 2>&1
        wait "$spinner_pid" >/dev/null 2>&1
        spinner_pid=
        if [[ -t 1 && ${TERM:-dumb} != dumb && "$timeline_active" == true &&
              "$timeline_dashboard_drawn" == true && "$timeline_header_rewrite_safe" == true ]]; then
            timeline_refresh_current
        elif [[ -t 1 ]]; then
            printf '\r\033[2K'
        fi
    fi
    if [[ "$had_errexit" == true ]]; then set -e; else set +e; fi
}

spinner_start() {
    spinner_clear
    spinner_label=$*
    timeline_advance_action
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
        (
            local stop_requested=false
            trap 'stop_requested=true' TERM INT
            while [[ "$stop_requested" != true ]]; do
                for frame in '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'; do
                    [[ "$stop_requested" != true ]] || break
                    if [[ "$timeline_active" == true && "$timeline_header_rewrite_safe" == true ]]; then
                        timeline_animate_processing_frame "$frame" "$spinner_label"
                    else
                        printf '\r\033[2K\033[1;34m%s\033[0m %s' "$frame" "$spinner_label"
                    fi
                    sleep 0.12 || true
                done
            done
        ) &
        spinner_pid=$!
    else
        printf '~ %s\n' "$spinner_label"
    fi
}

spinner_stop() {
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
        spinner_clear
    fi
    spinner_label=
}

format_time_left() {
    local seconds=$1 hours minutes
    if (( seconds < 60 )); then
        printf '1m remaining'
    elif (( seconds < 3600 )); then
        printf '%dm remaining' "$(( (seconds + 59) / 60 ))"
    else
        hours=$((seconds / 3600))
        minutes=$(((seconds % 3600 + 59) / 60))
        if (( minutes == 60 )); then
            hours=$((hours + 1))
            minutes=0
        fi
        if (( minutes > 0 )); then
            printf '%dh %dm remaining' "$hours" "$minutes"
        else
            printf '%dh remaining' "$hours"
        fi
    fi
}

timeline_standard_step_seconds() {
    case "$1" in
        1) printf '720' ;; # reset, two setup sessions, authentication, and SSH
        2) printf '30'  ;; # baseline validation
        3) printf '240' ;; # download and build the 2.1 GB compatibility payload
        4) printf '60'  ;; # rollback capture and guards
        5) printf '360' ;; # native module build and storage-state preparation
        6) printf '240' ;; # identity and Drive package installation
        7) printf '30'  ;; # pre-storage service validation
        8) printf '180' ;; # first reboot and validation
        9) printf '240' ;; # handoff, second reboot, and discovery validation
        *) printf '60'  ;;
    esac
}

timeline_calculated_remaining_seconds() {
    local current_weight future=0 span completed_within remaining_current step
    current_weight=$(timeline_standard_step_seconds "$timeline_current_number")
    for ((step = timeline_current_number + 1; step <= 9; step++)); do
        future=$((future + $(timeline_standard_step_seconds "$step")))
    done
    span=$((timeline_step_ceiling_tenths - timeline_step_base_tenths))
    completed_within=$((timeline_percentage_tenths - timeline_step_base_tenths))
    if (( span > 0 )); then
        remaining_current=$((current_weight * (span - completed_within) / span))
    else
        remaining_current=$current_weight
    fi
    printf '%d' "$((remaining_current + future))"
}

timeline_reset_eta_anchor() {
    timeline_eta_anchor_seconds=$SECONDS
    timeline_eta_anchor_remaining=$(timeline_calculated_remaining_seconds)
}

timeline_refresh_time_left() {
    local elapsed remaining
    elapsed=$((SECONDS - timeline_eta_anchor_seconds))
    remaining=$((timeline_eta_anchor_remaining - elapsed))
    (( remaining >= 60 )) || remaining=60
    timeline_time_left=$(format_time_left "$remaining")
}

timeline_action_budget_for() {
    local current=$1 total=$2 label=$3
    if (( current == 1 )); then
        printf '20'
    else
        case "$current" in
            2) printf '1' ;;
            3) printf '2' ;;
            4) printf '3' ;;
            5) printf '5' ;;
            6) printf '2' ;;
            7) printf '1' ;;
            8) printf '3' ;;
            9) printf '5' ;;
            *) printf '3' ;;
        esac
    fi
}

timeline_percentage_text() {
    if (( timeline_percentage_tenths % 10 == 0 )); then
        printf '%d' "$((timeline_percentage_tenths / 10))"
    else
        printf '%d.%d' "$((timeline_percentage_tenths / 10))" "$((timeline_percentage_tenths % 10))"
    fi
}

timeline_render_progress() {
    local percentage_text filled column bar_width=24
    if (( timeline_percentage_tenths >= 1000 )); then
        timeline_time_left='0m remaining'
    else
        timeline_refresh_time_left
    fi
    percentage_text=$(timeline_percentage_text)
    filled=$((timeline_percentage_tenths * bar_width / 1000))
    printf '\r\033[2K'
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
        for ((column = 0; column < bar_width; column++)); do
            if (( column < filled )); then
                printf '\033[2;37m█\033[0m'
            else
                printf '\033[2;90m░\033[0m'
            fi
        done
        printf ' '
        printf '\033[2;37m%s%% Complete\033[0m' "$percentage_text"
        printf '\033[2;90m  %s\033[0m\n' "$timeline_time_left"
    else
        for ((column = 0; column < bar_width; column++)); do
            if (( column < filled )); then printf '#'; else printf '-'; fi
        done
        printf ' %s%% Complete  %s\n' "$percentage_text" "$timeline_time_left"
    fi
}

timeline_render_step_row() {
    local step=$1 active_frame=${2:-⠋} title
    title=${timeline_step_titles[$((step - 1))]}
    printf '\r\033[2K'
    if (( step < timeline_current_number )); then
        if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
            printf '\033[1;32m✓\033[0m\033[2;37m  %s\033[0m\n' "$title"
        else
            printf '✓  %s\n' "$title"
        fi
    elif (( step == timeline_current_number )) && [[ "$timeline_active" == true ]]; then
        if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
            printf '\033[1;97m%s  %s\033[0m\n' "$active_frame" "$title"
        else
            printf '~  %s\n' "$title"
        fi
    else
        if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
            printf '\033[2;37m○  %s\033[0m\n' "$title"
        else
            printf '○  %s\n' "$title"
        fi
    fi
}

timeline_render_dashboard() {
    local active_frame=${1:-⠋} step child_rendered=false
    if [[ "$timeline_dashboard_drawn" == true ]]; then
        printf '\r\033[2K\033[%dA\r' "$timeline_dashboard_rows"
    else
        printf '\n'
    fi
    timeline_render_progress
    printf '\r\033[2K\n'
    for ((step = 1; step <= 9; step++)); do
        timeline_render_step_row "$step" "$active_frame"
        if (( step == timeline_current_number )) && [[ "$timeline_active" == true ]]; then
            printf '\r\033[2K\n'
            child_rendered=true
        fi
    done
    if [[ "$child_rendered" == false ]]; then
        printf '\r\033[2K\n'
    fi
    timeline_dashboard_drawn=true
}

timeline_animate_processing_frame() {
    local frame=$1 label=$2 distance
    [[ "$timeline_active" == true && "$timeline_header_rewrite_safe" == true ]] || return 0
    [[ -t 1 && ${TERM:-dumb} != dumb ]] || return 0
    (( timeline_current_number >= 1 && timeline_current_number <= 9 )) || return 0
    distance=$((timeline_dashboard_rows - timeline_current_number - 1))
    printf '\0337\r\033[%dA\033[1;97m%s\033[0m\033[1B\r\033[2K' \
        "$distance" "$frame"
    printf '\033[2;37m╰─ \033[0m\033[1;34m%s\033[0m  %s\0338' "$frame" "$label"
}

timeline_refresh_current() {
    [[ "$timeline_active" == true && "$timeline_header_rewrite_safe" == true ]] || return 0
    [[ -t 1 && ${TERM:-dumb} != dumb ]] || return 0
    timeline_render_dashboard
}

timeline_advance_action() {
    local span advance next
    [[ "$timeline_active" == true && "$timeline_header_rewrite_safe" == true ]] || return 0
    [[ -t 1 && ${TERM:-dumb} != dumb ]] || return 0
    timeline_action_index=$((timeline_action_index + 1))
    span=$((timeline_step_ceiling_tenths - timeline_step_base_tenths))
    advance=$((span * timeline_action_index / (timeline_action_budget + 1)))
    next=$((timeline_step_base_tenths + advance))
    if (( next >= timeline_step_ceiling_tenths )); then
        next=$((timeline_step_ceiling_tenths - 1))
    fi
    if (( next > timeline_percentage_tenths )); then
        timeline_percentage_tenths=$next
        timeline_reset_eta_anchor
        timeline_refresh_current
    fi
}

timeline_complete_current() {
    local completed_through
    [[ "$timeline_active" == true ]] || return 0
    spinner_clear
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
        completed_through=$timeline_current_number
        timeline_percentage_tenths=$timeline_step_ceiling_tenths
        timeline_current_number=$((completed_through + 1))
        timeline_active=false
        timeline_render_dashboard
    else
        printf '✓  %s\n' "$timeline_label"
    fi
    timeline_active=false
    timeline_header_rewrite_safe=false
}

timeline_step() {
    local current=$1 total=$2 label=$3 completed
    (( total == 9 )) || die 'internal timeline must contain exactly nine steps'
    if [[ "$timeline_active" == true && "$current" -eq "$timeline_current_number" && "$total" -eq "$timeline_current_total" ]]; then
        timeline_refresh_current
        return 0
    fi
    if (( timeline_sequence_started < 0 || current <= 1 || total != timeline_last_total || current <= timeline_last_number )); then
        timeline_sequence_started=$SECONDS
    fi
    completed=$((current - 1))
    timeline_active=true
    timeline_label=${timeline_step_titles[$completed]}
    timeline_current_number=$current
    timeline_current_total=$total
    timeline_step_base_tenths=$((completed * 1000 / total))
    timeline_step_ceiling_tenths=$((current * 1000 / total))
    timeline_percentage_tenths=$timeline_step_base_tenths
    timeline_action_index=0
    timeline_action_budget=$(timeline_action_budget_for "$current" "$total" "$label")
    timeline_last_number=$current
    timeline_last_total=$total
    timeline_header_rewrite_safe=true
    timeline_reset_eta_anchor
    timeline_render_dashboard
}

log() {
    [[ "$timeline_active" != true ]] || timeline_header_rewrite_safe=false
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
        printf '\033[2;37m%s\033[0m\n' "$*"
    else
        printf '%s\n' "$*"
    fi
}
die() { spinner_clear; printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "required macOS command not found: $1"; }

timeline_input_prompt_begin() {
    local label=$1 child_label
    child_label=${1%: }
    timeline_animate_processing_frame '⠋' "Waiting for $child_label"
    printf '\n\033[1;33m%s\033[0m' "$label"
}

timeline_input_prompt_finish() {
    printf '\r\033[2K\033[1A\r\033[2K\033[1A\r'
    timeline_render_dashboard
}

timeline_read_input() {
    local label=$1 variable=$2 secret=$3 value='' rc read_rc opener_pid input_fifo
    input_fifo="$temp_root/input.fifo"
    timeline_input_prompt_begin "$label"
    rm -f -- "$input_fifo"
    mkfifo -m 600 "$input_fifo" || die 'could not create private terminal input channel'
    (: > "$input_fifo") &
    opener_pid=$!
    exec 8<"$input_fifo" || die 'could not open private terminal input channel'
    wait "$opener_pid" || die 'could not initialize private terminal input channel'
    exec 9>"$input_fifo" || die 'could not open private terminal result channel'
    set +e
    python3 -c '
import os
import select
import sys
import termios

label = sys.argv[1]
secret = sys.argv[2] == "true"
current_step = int(sys.argv[3])
dashboard_rows = int(sys.argv[4])
child_label = "Waiting for " + label.rstrip().rstrip(":")
frames = ("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")
value = bytearray()
frame_index = 0
escape_sequence = False
input_fd = sys.stdin.fileno()
output_fd = sys.stderr.fileno()
result_fd = 9
original = termios.tcgetattr(input_fd)
updated = termios.tcgetattr(input_fd)
columns = os.get_terminal_size(output_fd).columns
updated[3] &= ~(termios.ICANON | termios.ECHO)
updated[6][termios.VMIN] = 0
updated[6][termios.VTIME] = 0

def visible_value():
    if secret:
        return ""
    text = value.decode("utf-8", "replace")
    limit = min(36, max(4, columns - len(label) - 1))
    return text if len(text) <= limit else "…" + text[-(limit - 1):]

def redraw(frame):
    distance = dashboard_rows - current_step
    line = (
        f"\0337\r\033[{distance}A\033[1;97m{frame}\033[0m"
        f"\033[1B\r\033[2K\033[2;37m╰─ \033[0m"
        f"\033[1;34m{frame}\033[0m  {child_label}\0338"
        f"\r\033[2K\033[1;33m{label}\033[0m"
    )
    shown = visible_value()
    if shown:
        line += f"\033[0;37m{shown}\033[0m"
    os.write(output_fd, line.encode("utf-8"))

try:
    termios.tcsetattr(input_fd, termios.TCSANOW, updated)
    redraw(frames[frame_index])
    finished = False
    while not finished:
        readable, _, _ = select.select([input_fd], [], [], 0.12)
        if readable:
            chunk = os.read(input_fd, 64)
            for byte in chunk:
                # escape_sequence: False, "esc" after ESC, "csi" inside ESC [ ... final,
                # or "ss3" after ESC O; bracketed paste wraps text in ESC[200~/ESC[201~.
                if escape_sequence == "esc":
                    if byte == 91:
                        escape_sequence = "csi"
                    elif byte == 79:
                        escape_sequence = "ss3"
                    elif 64 <= byte <= 126:
                        escape_sequence = False
                    continue
                if escape_sequence == "ss3":
                    escape_sequence = False
                    continue
                if escape_sequence == "csi":
                    if 64 <= byte <= 126:
                        escape_sequence = False
                    continue
                if byte == 27:
                    escape_sequence = "esc"
                elif byte in (10, 13):
                    finished = True
                    break
                elif byte in (8, 127):
                    if value:
                        value.pop()
                        while value and (value[-1] & 0xC0) == 0x80:
                            value.pop()
                elif byte == 21:
                    value.clear()
                elif byte >= 32:
                    if len(value) < 512:
                        value.append(byte)
        frame_index = (frame_index + 1) % len(frames)
        redraw(frames[frame_index])
except KeyboardInterrupt:
    sys.exit(130)
finally:
    termios.tcsetattr(input_fd, termios.TCSANOW, original)

os.write(result_fd, bytes(value) + b"\0")
' "$label" "$secret" "$timeline_current_number" "$timeline_dashboard_rows"
    rc=$?
    exec 9>&-
    value=
    read_rc=1
    if [[ "$rc" -eq 0 ]]; then
        IFS= read -r -d '' value <&8
        read_rc=$?
    fi
    exec 8<&-
    rm -f -- "$input_fifo"
    set -e
    if [[ "$rc" -ne 0 && "$interrupt_declined" == true ]]; then
        interrupt_declined=false
        timeline_read_input "$label" "$variable" "$secret"
        return
    fi
    [[ "$rc" -eq 0 && "$read_rc" -eq 0 ]] || die 'terminal input failed'
    printf -v "$variable" '%s' "$value"
    printf '\n'
    timeline_input_prompt_finish
}

prompt_value() {
    local label=$1 variable=$2
    timeline_advance_action
    if [[ -t 1 && ${TERM:-dumb} != dumb && "$timeline_active" == true &&
          "$timeline_dashboard_drawn" == true && "$timeline_header_rewrite_safe" == true ]]; then
        timeline_read_input "$label" "$variable" false
        return
    fi
    printf '\n'
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
        printf '\033[1;33m%s\033[0m' "$label"
    else
        printf '%s' "$label"
    fi
    IFS= read -r "${variable?}"
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
        printf '\033[2A\r\033[J'
    fi
}

prompt_secret() {
    local label=$1 variable=$2
    timeline_advance_action
    if [[ -t 1 && ${TERM:-dumb} != dumb && "$timeline_active" == true &&
          "$timeline_dashboard_drawn" == true && "$timeline_header_rewrite_safe" == true ]]; then
        timeline_read_input "$label" "$variable" true
        return
    fi
    printf '\n'
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
        printf '\033[1;33m%s\033[0m' "$label"
    else
        printf '%s' "$label"
    fi
    IFS= read -r -s "${variable?}"
    printf '\n'
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
        printf '\033[2A\r\033[J'
    fi
}

print_conversion_title() {
    printf '\n'
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
        printf '\033[1;30;47m UniFi UNVR to UNAS Pro Conversion \033[0m\n\n'
    else
        printf '=== UniFi UNVR to UNAS Pro Conversion ===\n\n'
    fi
}

print_target_summary() {
    printf '\n'
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
        printf '\033[1;97mTarget: UNVR\033[0m\n'
        printf '\033[1;97mIP: %s\033[0m\n' "$unvr_ip"
        printf '\033[2;37mzero-to-four installed drives will be preserved until UNAS setup.\033[0m\n'
    else
        printf 'Target: UNVR\n'
        printf 'IP: %s\n' "$unvr_ip"
        printf 'zero-to-four installed drives will be preserved until UNAS setup.\n'
    fi
    printf '\n'
}

reset_box_line() {
    printf '│ %-76.76s │\n' "$1"
}

print_box_border() {
    local left=$1 right=$2 column
    printf '%s' "$left"
    for ((column = 0; column < 78; column++)); do
        printf '─'
    done
    printf '%s\n' "$right"
}

reset_box_heading() {
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
        printf '│ \033[1m%-76s\033[0m │\n' "$1"
    else
        reset_box_line "$1"
    fi
}

reset_box_colored_heading() {
    local color=$1 label=$2
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
        printf '│ \033[1;%sm%-76s\033[0m │\n' "$color" "$label"
    else
        reset_box_line "$label"
    fi
}

print_destructive_reset_box() {
    print_box_border '┌' '┐'
    reset_box_colored_heading 31 'What will be erased'
    reset_box_line '  - UNVR console configuration'
    reset_box_line '  - All data on every installed SATA drive'
    reset_box_line '  - RAID metadata, storage pools, shares, recordings, and backups'
    reset_box_line ''
    reset_box_heading 'What will be preserved'
    reset_box_line '  - The Network site and all other controller devices and clients'
    reset_box_line ''
    reset_box_colored_heading 32 'What will not be modified'
    reset_box_line '  - Recovery kernel and recovery environment'
    reset_box_line '  - Physical hardware identity'
    reset_box_line ''
    reset_box_heading 'Firmware normalization'
    reset_box_line '  - Other supported OS versions are normalized to signed UNVR 5.1.33'
    reset_box_line '  - The stock updater may replace UNVR U-Boot and reset its environment'
    reset_box_line '  - Official firmware images are hash-verified and never patched'
    reset_box_line ''
    reset_box_heading 'Console cleanup'
    reset_box_line '  - Unregisters this UNVR console from Site Manager'
    reset_box_line '  - Forgets only this UNVR client when its Network site is accessible'
    reset_box_line '  - An empty Site Manager shell may remain and can be reused for UNAS'
    reset_box_line ''
    reset_box_colored_heading 34 'Authentication and privacy'
    reset_box_line '  - Automates normal UI Account sign-in, MFA, and local console setup'
    reset_box_line '  - Creates temporary ownership, enables SSH, and disables auto-updates'
    reset_box_line '  - Authenticates the original Network controller for client cleanup'
    reset_box_line '  - Unregisters temporary ownership before official UNAS setup'
    reset_box_line '  - Password and MFA code stay only in memory and are cleared on exit'
    reset_box_line '  - Never written to disk, logs, command arguments, or the payload'
    reset_box_line '  - Sent only over HTTPS to local UniFi services and Ubiquiti UI'
    reset_box_line '    identity services used by the normal sign-in flow'
    reset_box_line '  - Private temporary session cookies are deleted when the script exits'
    reset_box_line ''
    reset_box_colored_heading 33 'Warranty and liability'
    reset_box_line '  - This unofficial conversion is not supported by Ubiquiti'
    reset_box_line '  - It will probably void any applicable Ubiquiti warranty'
    reset_box_line '  - The author is not liable for data loss, hardware damage, service loss,'
    reset_box_line '    or any other damages resulting from use of this script'
    print_box_border '└' '┘'
}

cleanup() {
    local rc=$?
    set +e
    spinner_clear
    if [[ "$temporary_update_ssh_configured" == true ]]; then
        if ! disable_update_ssh >/dev/null 2>&1; then
            printf '\nTemporary SSH cleanup failed. Disable SSH in UniFi Control Plane.\n' >&2
            rc=1
        fi
    fi
    if [[ -n "$askpass_writer_pid" ]]; then
        kill "$askpass_writer_pid" >/dev/null 2>&1 || true
        wait "$askpass_writer_pid" >/dev/null 2>&1 || true
        askpass_writer_pid=
    fi
    if [[ -n "$control_socket" && -S "$control_socket" ]]; then
        ssh -S "$control_socket" -O exit "root@$unvr_ip" >/dev/null 2>&1
    fi
    if [[ -n "$temp_root" && -d "$temp_root" && "$temp_root" == /private/tmp/unvr-unas-installer.* ]]; then
        rm -rf -- "$temp_root"
    fi
    if [[ -n "$execution_snapshot_dir" && -d "$execution_snapshot_dir" &&
          "$execution_snapshot_dir" == /private/tmp/unvr-unas-exec.* ]]; then
        rm -rf -- "$execution_snapshot_dir"
    fi
    ssh_password=
    ui_account=
    ui_account_password=
    mfa_token=
    controller_client_mac=
    controller_site=
    controller_cleanup_mode=unresolved
    exit "$rc"
}

reenable_errexit_after_interrupt() {
    if [[ "$interrupt_reenable_errexit" == true && "${FUNCNAME[1]:-}" != confirm_interrupt ]]; then
        interrupt_reenable_errexit=false
        trap - DEBUG
        set -e
    fi
}

confirm_interrupt() {
    local answer='' resume_label had_errexit=false
    resume_label=$spinner_label
    if [[ "$interrupt_prompt_active" == true ]]; then
        return 0
    fi
    interrupt_prompt_active=true
    [[ $- == *e* ]] && had_errexit=true
    set +e
    spinner_clear
    while :; do
        printf '\n\033[1;33mAre you sure you want to stop the conversion? [y/N] \033[0m'
        IFS= read -r answer
        case "$answer" in
            y|Y|yes|YES|Yes)
                trap - INT
                exit 130
                ;;
            ''|n|N|no|NO|No)
                interrupt_declined=true
                interrupt_prompt_active=false
                if [[ -t 1 && ${TERM:-dumb} != dumb && "$timeline_dashboard_drawn" == true ]]; then
                    printf '\033[H\033[2J\033[3J'
                    print_conversion_title
                    print_target_summary
                    timeline_dashboard_drawn=false
                    timeline_render_dashboard
                else
                    printf '\n\033[2;37mContinuing conversion.\033[0m\n'
                fi
                if [[ -n "$resume_label" ]]; then
                    if (( timeline_action_index > 0 )); then
                        timeline_action_index=$((timeline_action_index - 1))
                    fi
                    spinner_start "$resume_label"
                fi
                if [[ "$had_errexit" == true ]]; then
                    interrupt_reenable_errexit=true
                    trap reenable_errexit_after_interrupt DEBUG
                else
                    set +e
                fi
                return 0
                ;;
            *) printf '\nPlease answer yes or no.\n' ;;
        esac
    done
}

trap cleanup EXIT HUP TERM
trap confirm_interrupt INT

validate_ipv4() {
    local ip=$1 old_ifs=$IFS octet decimal count=0 first=
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    IFS=.
    for octet in $ip; do
        count=$((count + 1))
        [[ ${#octet} -eq 1 || "$octet" != 0* ]] || { IFS=$old_ifs; return 1; }
        decimal=$((10#$octet))
        [[ "$decimal" -ge 0 && "$decimal" -le 255 ]] || { IFS=$old_ifs; return 1; }
        [[ -n "$first" ]] || first=$decimal
    done
    IFS=$old_ifs
    [[ "$count" -eq 4 && "$first" -ge 1 && "$first" -le 223 && "$first" -ne 127 ]]
}

parse_args() {
    if [[ $# -gt 0 ]]; then
        case "$1" in
            prepare-os-update|arm-stage1|arm-stage2)
                die 'OS updates are not supported by this fixed UNAS Pro 5.1.33 release' ;;
            install|setup-only|status|disarm|rollback|unadopt) command=$1; shift ;;
        esac
    fi
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ip) [[ $# -ge 2 ]] || die '--ip requires a value'; unvr_ip=$2; shift 2 ;;
            --controller-ip) [[ $# -ge 2 ]] || die '--controller-ip requires a value'; controller_ip=$2; shift 2 ;;
            --skip-controller-cleanup) skip_controller_cleanup=true; shift ;;
            --prebuilt-modules) [[ $# -ge 2 ]] || die '--prebuilt-modules requires a directory'; prebuilt_modules=$2; shift 2 ;;
            --artifact-cache) [[ $# -ge 2 ]] || die '--artifact-cache requires a directory'; artifact_cache=$2; shift 2 ;;
            --unas-firmware) die 'use --unas-5-firmware with the exact UNAS Pro 5.1.33 image' ;;
            --unvr-5-firmware) [[ $# -ge 2 ]] || die '--unvr-5-firmware requires a file'; unvr5_firmware=$2; shift 2 ;;
            --unas-5-firmware) [[ $# -ge 2 ]] || die '--unas-5-firmware requires a file'; unas5_firmware=$2; shift 2 ;;
            --dry-run) dry_run=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "unknown argument: $1" ;;
        esac
    done
    [[ "$command" == install || ( -z "$unas_firmware" && -z "$unvr5_firmware" && -z "$unas5_firmware" ) ]] || die 'firmware file options are only valid with install'
    [[ "$command" == install || -z "$controller_ip" ]] || die '--controller-ip is only valid with install'
    [[ "$command" == install || "$skip_controller_cleanup" == false ]] || die '--skip-controller-cleanup is only valid with install'
    [[ -z "$controller_ip" || "$skip_controller_cleanup" == false ]] || die '--controller-ip and --skip-controller-cleanup are mutually exclusive'
    [[ "$command" == install || ( -z "$prebuilt_modules" && -z "$artifact_cache" ) ]] || die '--prebuilt-modules and --artifact-cache are only valid with install'
    [[ -z "$prebuilt_modules" || -d "$prebuilt_modules" ]] || die "--prebuilt-modules directory not found: $prebuilt_modules"
    [[ -z "$artifact_cache" || -d "$artifact_cache" ]] || die "--artifact-cache directory not found: $artifact_cache"
    [[ "$command" == install || "$dry_run" == false ]] || die '--dry-run is only valid with install'
}

check_macos() {
    [[ $(uname -s) == Darwin ]] || die 'this orchestrator currently supports macOS only'
    [[ ${#TEMPORARY_SSH_PASSWORD} -ge 12 && ${#TEMPORARY_SSH_PASSWORD} -le 128 &&
       "$TEMPORARY_SSH_PASSWORD" =~ [A-Z] && "$TEMPORARY_SSH_PASSWORD" =~ [a-z] &&
       "$TEMPORARY_SSH_PASSWORD" =~ [0-9] ]] \
        || die 'internal temporary SSH password violates the UniFi OS policy'
    require_command ssh
    require_command shasum
    require_command mkfifo
    require_command curl
    require_command nc
    require_command jq
    require_command awk
    require_command sed
    require_command cut
    require_command tr
    require_command stat
    require_command mktemp
    require_command ar
    require_command tar
    require_command gzip
    require_command unsquashfs
    require_command xz
    require_command node
    require_command python3
    [[ -f "$remote_engine" ]] || die "missing remote engine: $remote_engine"
    [[ -x "$profile_builder" ]] || die "missing update profile builder: $profile_builder"
    [[ $(sha "$remote_engine") == "$REMOTE_ENGINE_SHA256" ]] || die 'remote engine hash mismatch'
    [[ $(sha "$profile_builder") == "$UPDATE_PROFILE_BUILDER_SHA256" ]] || die 'update profile builder hash mismatch'
    [[ $(sha "$script_dir/debian_drive_closure.tsv") == "$DEBIAN_DRIVE_CLOSURE_SHA256" ]] || die 'immutable Debian closure manifest hash mismatch'
    [[ $(sha "$script_dir/debian_kbuild_closure.tsv") == "$DEBIAN_KBUILD_CLOSURE_SHA256" ]] || die 'immutable kernel-build manifest hash mismatch'
    [[ $(sha "$script_dir/verify_payload_contract.py") == "$PAYLOAD_CONTRACT_SHA256" ]] || die 'payload verifier hash mismatch'
    [[ $(sha "$script_dir/ubiquiti_drive_packages.tsv") == "$UBIQUITI_DRIVE_PACKAGES_SHA256" ]] || die 'immutable Ubiquiti package manifest hash mismatch'
    [[ $(sha "$script_dir/build_core_unaspro_identity_patch.js") == "$CORE_IDENTITY_BUILDER_SHA256" ]] || die 'Core identity builder hash mismatch'
    [[ $(sha "$script_dir/build_core_5x_unaspro_patch.js") == "$CORE_5X_BUILDER_SHA256" ]] || die 'Core 5.x builder hash mismatch'
    [[ $(sha "$script_dir/build_5x_identity_overlays.py") == "$IDENTITY_OVERLAY_BUILDER_SHA256" ]] || die 'identity overlay builder hash mismatch'
    [[ $(sha "$script_dir/patch_portal_unaspro_manifest.js") == "$PORTAL_BUILDER_SHA256" ]] || die 'portal identity builder hash mismatch'
    [[ $(sha "$script_dir/verify_storage_ui_contract.js") == "$STORAGE_UI_VERIFIER_SHA256" ]] || die 'storage UI contract verifier hash mismatch'
    [[ $(sha "$script_dir/build_wsdd_5x_debs_macos.sh") == "$WSDD5_BUILDER_SHA256" ]] || die 'UNAS 5.x wsdd builder hash mismatch'
    [[ $(sha "$script_dir/query_drive_storage_state.js") == "$DRIVE_STORAGE_QUERY_SHA256" ]] || die 'Drive storage v2 query hash mismatch'
    [[ $(sha "$script_dir/ensure_unas_identity_at_boot.sh") == "$IDENTITY_RESTORE_SHA256" ]] || die 'identity restore hash mismatch'
    [[ $(sha "$script_dir/restore_drive_after_base_update.sh") == "$DRIVE_RESTORE_SHA256" ]] || die 'Drive restore hash mismatch'
    [[ $(sha "$script_dir/unifi-drive-launcher") == "$DRIVE_LAUNCHER_SHA256" ]] || die 'Drive launcher hash mismatch'
    [[ $(sha "$script_dir/unifi-drive-ubnt-tools") == "$DRIVE_IDENTITY_ADAPTER_SHA256" ]] || die 'Drive identity adapter hash mismatch'
    [[ $(sha "$script_dir/unvr-unas-identity-restore.service") == "$IDENTITY_UNIT_SHA256" ]] || die 'identity restore unit hash mismatch'
    [[ $(sha "$script_dir/unvr-unas-drive-restore.service") == "$DRIVE_UNIT_SHA256" ]] || die 'Drive restore unit hash mismatch'
    [[ $(sha "$script_dir/guarded-fwupdate") == "$GUARDED_FWUPDATE_SHA256" ]] || die 'guarded updater hash mismatch'
    [[ $(sha "$script_dir/logical_unadopt.sh") == "$LOGICAL_UNADOPT_SHA256" ]] || die 'logical unadoption helper hash mismatch'
    [[ $(sha "$script_dir/readopt_ssh_restorer.sh") == "$READOPT_SSH_RESTORER_SHA256" ]] || die 'readoption finalizer hash mismatch'
    [[ $(sha "$script_dir/unvr-unas-readopt-ssh.service") == "$READOPT_SSH_UNIT_SHA256" ]] || die 'readoption finalizer unit hash mismatch'
}

materialize_embedded_helpers() {
    local archive="$temp_root/embedded-helpers.tar.gz" member
    script_dir="$temp_root/helpers"
    install -d -m 0700 "$script_dir"
    base64 -D > "$archive" <<'UNVR_UNAS_EMBEDDED_HELPERS'
H4sIAAAAAAAA/+y9eWNbx5EvOv+Cn+IEUUwyFsBezyKHmafY8sRvHMtPsme5tofplUJEAgwWWbKs
fPb3qz4LDjaScpzkzr3DxCJxTi/V1dVVv6qubtjV5Mpf6NcXEx+my8nyzcXsVZhfmTeL8c2bf/p5
fhh+Cq3Tb/xs/y4kE//EtchzLqQU+T8xrrXm/5Sxn6n/W39Wi6WZg5T5bLa8rdxd7/+b/vzyF2er
xfzMTqZnYfoqu3mzfDGbyqPhcPg7kowsvDZumakxP9Pj19nXn3+ZmanPvv7sk6yVkyzO5pnJbl68
WUycucq+/uLfnmVXs9nL1c0YzRwdxfnsOru4iKvlah4uLrLJ9c1svkQ709nSLCez6eLoqHn2wixe
XE1s+/FPi9m0/XvxZlG3dGOWVKZt5kt8PDo6+vLZ008/+/zJ8+w8e3uU4eck/Us/w7yw2sa8UNyE
GExZslKVRfTSWiZFtIpxF7QIJlS+cGVe5lVRVj6PqjKlDuXw4bqtKnci904ZxiULpmAFt7EwWgtf
8FLEKCDIMtdc6igFL3UlCm+KKg9e59z4pq3TR30Cma+CC4yjuPNMoXcHmnKtlLWGV05b6U1Z2byo
0FfucuuijibyvCy847xPoGEhZ854LyXeOINaunRW8zy3pQulsboyRgRdRpt7ryV3XORKVpVWzBQd
gQ+3uYh3Ns+dFlbxMlhZWSdinoMQV8iowQJWSiGLMpcxBqdZrAQPLkomvQ1S94lUxjnLTGSqNKgp
fLBVjMzlzLBoq9IVwldGhehZNEXAbAnOeRErZb3x3O7lohLKFaBImgrTk2tdeFlUXhWVUoVUqpQh
MFmpvAjWWuk0pk8zm8eqCjRZfQJF5VCwkl7pMveCSS1cZUIQwrEyGh5BolQmLyMYWVZMew2+Mmus
80UZizUX30E4fYjZ4oUROj8h6X2UhPY0G/02Wyznj1LJecDqmLYLYNwrPZ4H4y/sm2VYnJyejl+E
135yGRbLk9Om5e/nk2W4oLXSa/1h9spcrcKjbGb/FNwydfbFbBrq3lK7db1leL08ocpjv7q+WZyk
ag+zyZTswbl4mC2wyi5ehjeL80/N1SKcZh9mw2+nw7b3azOZnqTmJ9Nl3fokZldheoIVOzbzy1en
2S/OM/2oY+7cTBYhe/5msQzXT15PluspTKxfLcwl6La3GSZSQBfPn3797OMnpJO6P/H06ddfffn1
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
n85+9Ze//OvZXVskOn8/nY3q3GMfAtcenmZXXz3cPt81efnmzbwtZhc/b88Ps8ebx9bTze2b9onM
ALO/+avrv/ybv3n3V2+e79L840x4/+YN90cf7jEdqzPMd1fDB32+/+rpgitmfba5bfj49DC+/d1n
q0tX63e2bW4f3l/zrW2b9ZxePDXM5VO7RJOde374Zn5T0u01ZmeOAS8/zGmlyb9avYuxfWBlyh9/
Mfvtmxn+Lf+cP9/N3n4m386+m6WvP84+/+3j0839YvaZ/N3nb3735g2+aPOBcaXPPv/RfPaj+f+4
/xyf+zGf5uziefaTH/0/Fz+6u/hR/c2P/suXP/rbL3/06//3i7do8B9540VDm4S/1iN7y1tzcjf3
xpXZ21/9/Bf/+Ouf//WXM3xsvNs+3Sxmko0JqujEP3zd6s6HMOpZKovndPvuM7ka1U1f7F5dfma8
0/GsV3/Pbu7Rn//09mez+jCu8d9//+94b3m7t7N37/jHsvXb2f/8n7M/+zPI7OL56X4mxicw+W28
WL07+rlSlxzkQTfnD89PBc9UzqBP3rfFu8/UrLb5zVOr7z7Ts7uHiotmO4aZOfrwNWdhVp6fniAO
s8Xd45tVry86+rps85b9/A+zi7/ZeQed/+67Ged79vbuZj6/uX9PsX++n6fO1Znec0I265aFODEL
eAyrGyw7te3Cu89+vBSe7Xd88WYzgTsNV7O4GuZ+R8597WwMEt284+n0QSfwBauxLSdxjPbHfK/t
vIfvGDOy/vsLfvH/2DzmTRc2371sOIOmuX9YzNJszMtTe/98m56GtkA3Vjcbd1k9gnd/+8tf//qX
f/efd7q2+7XL0a7b7szZqsHOnK0anZivQ6nbXQi7H1x1ZQj1doTP90+tPLy/v/kWrVejzA3rYEdP
r3TKwRAhXejy3UcoyUfc9LfLa7+7XKq1lRr6b+PfaiA393ikt7ezi4cZbeHs4v3qNxUMxfvtjkhi
Eu4e324nYGdy8P4X30NwVqM5lJbdMdx9tXoguOV22rf6ZjWMOvvsxzz5JYXZztN5u7Oe69PNV+16
afCuF4C71/bT6fV9Nae5fM73iwu2m29W+1qXj1sxGIlnb7c7Lb/nYsY7F5/2F/cJ0V6a3J1utE+t
PC9Svm0U8yMtcPJRrNf2eBpZkrfPjkMZHrqzYE5koCcT1ZUeXDiMTigww3B+vG6yNJZgaYDpNrTf
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
UNVR_UNAS_EMBEDDED_HELPERS
    [[ "$(sha "$archive")" == "$EMBEDDED_HELPERS_SHA256" ]] \
        || die 'embedded helper payload hash mismatch'
    while IFS= read -r member; do
        [[ "$member" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
            || die 'embedded helper payload contains an unsafe path'
    done < <(tar -tzf "$archive")
    tar -xzf "$archive" -C "$script_dir" --no-same-owner
    chmod 0755 \
        "$script_dir/unvr_unas_remote.sh" \
        "$script_dir/build_update_profiles_macos.sh" \
        "$script_dir/build_wsdd_5x_debs_macos.sh" \
        "$script_dir/ensure_unas_identity_at_boot.sh" \
        "$script_dir/restore_drive_after_base_update.sh" \
        "$script_dir/unifi-drive-launcher" \
        "$script_dir/unifi-drive-ubnt-tools" \
        "$script_dir/guarded-fwupdate" \
        "$script_dir/logical_unadopt.sh" \
        "$script_dir/readopt_ssh_restorer.sh"
    remote_engine="$script_dir/unvr_unas_remote.sh"
    profile_builder="$script_dir/build_update_profiles_macos.sh"
}

prompt_ip() {
    if [[ -z "$unvr_ip" ]]; then
        prompt_value 'UNVR IPv4 address: ' unvr_ip
    fi
    validate_ipv4 "$unvr_ip" || die 'invalid IPv4 address'
    if [[ -n "$controller_ip" ]]; then
        validate_ipv4 "$controller_ip" || die 'invalid UniFi Network controller IPv4 address'
        [[ "$controller_ip" != "$unvr_ip" ]] || die 'the Network controller and UNVR cannot use the same address'
    fi
}

prompt_ssh_password() {
    ssh_password=$TEMPORARY_SSH_PASSWORD
}

public_system() {
    curl -ksS --connect-timeout 10 --max-time 30 "https://$unvr_ip/api/system"
}

local_api_request() {
    local method=$1 path=$2 status csrf_token new_csrf curl_rc
    if [[ -s "$api_csrf" ]]; then
        IFS= read -r csrf_token < "$api_csrf"
    fi
    set +e
    if [[ -n "$csrf_token" ]]; then
        printf 'X-CSRF-Token: %s\n' "$csrf_token" > "$api_csrf_header"
        chmod 0600 "$api_csrf_header"
        status=$(curl -ksS \
            --connect-timeout 10 \
            --max-time "${local_api_timeout:-900}" \
            -b "$api_cookie" \
            -c "$api_cookie" \
            -D "$api_headers" \
            -X "$method" \
            -H 'Content-Type: application/json' \
            -H "Origin: https://$unvr_ip" \
            -H "Referer: https://$unvr_ip/" \
            -H "@$api_csrf_header" \
            --data-binary @- \
            -o "$api_response" \
            -w '%{http_code}' \
            "https://$unvr_ip$path" 2>/dev/null)
        curl_rc=$?
    else
        rm -f -- "$api_csrf_header"
        status=$(curl -ksS \
            --connect-timeout 10 \
            --max-time "${local_api_timeout:-900}" \
            -b "$api_cookie" \
            -c "$api_cookie" \
            -D "$api_headers" \
            -X "$method" \
            -H 'Content-Type: application/json' \
            -H "Origin: https://$unvr_ip" \
            -H "Referer: https://$unvr_ip/" \
            --data-binary @- \
            -o "$api_response" \
            -w '%{http_code}' \
            "https://$unvr_ip$path" 2>/dev/null)
        curl_rc=$?
    fi
    set -e
    if [[ "$curl_rc" -ne 0 ]]; then
        printf '000'
        return 0
    fi
    new_csrf=
    if [[ -f "$api_headers" ]]; then
        new_csrf=$(awk '
            tolower($1) == "x-csrf-token:" ||
            tolower($1) == "x-updated-csrf-token:" ||
            tolower($1) == "x-expected-csrf-token:" {
                sub(/^[^:]+:[[:space:]]*/, "")
                sub(/\r$/, "")
                token=$0
            }
            END { print token }
        ' "$api_headers")
    fi
    if [[ -n "$new_csrf" ]]; then
        printf '%s\n' "$new_csrf" > "$api_csrf"
        chmod 0600 "$api_csrf"
    fi
    printf '%s' "$status"
}

controller_api_request() {
    local method=$1 path=$2
    local local_api_timeout=30
    local unvr_ip=$controller_ip
    local api_cookie=$controller_api_cookie
    local api_response=$controller_api_response
    local api_headers=$controller_api_headers
    local api_csrf=$controller_api_csrf
    local api_csrf_header=$controller_api_csrf_header
    local_api_request "$method" "$path"
}

require_controller_api_success() {
    local status=$1 label=$2 code
    case "$status" in 200|201|202|204) return 0 ;; esac
    code=$(jq -r '.code // .errorData.code // .err.code // .meta.msg // "unrecognized"' \
        "$controller_api_response" 2>/dev/null || printf unrecognized)
    die "$label failed with HTTP $status ($code)"
}

require_api_success() {
    local status=$1 label=$2 code
    case "$status" in 200|201|202|204) return 0 ;; esac
    code=$(jq -r '.code // .errorData.code // .err.code // "unrecognized"' "$api_response" 2>/dev/null || printf unrecognized)
    die "$label failed with HTTP $status ($code)"
}

validate_factory_public_state() {
    local system_json=$1
    jq -e '
        .deviceState == "notSetup" and
        .name == "UNVR" and
        (.hardware.firmwareVersion | type == "string" and length > 0) and
        ((.hardware.shortname // .hardware.shortName // .hardware.model) | type == "string" and test("^UNVR(4)?$")) and
        (.ustorage.disks | type) == "array" and
        ([.ustorage.disks[] | (.slot // .slotId // .slot_id)] | all(type == "number" and . >= 1 and . <= 4)) and
        ([.ustorage.disks[] | (.slot // .slotId // .slot_id)] | unique | length) ==
            ([.ustorage.disks[] | (.slot // .slotId // .slot_id)] | length)
    ' <<<"$system_json" >/dev/null \
        || die 'factory detector requires an unconfigured four-bay UNVR with a valid zero-to-four-bay storage inventory'
}

prompt_bootstrap_credentials() {
    if [[ -z "$ui_account" ]]; then
        prompt_value 'UI Account username or email: ' ui_account
        ui_account=$(printf '%s' "$ui_account" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -n "$ui_account" && ! "$ui_account" =~ [[:space:]] ]] \
            || die 'invalid UI Account username or email'
    fi
    while [[ -z "$ui_account_password" ]]; do
        prompt_secret 'UI Account password: ' ui_account_password
        [[ -n "$ui_account_password" ]] || log 'The password was empty; please enter it again.'
    done
    ssh_password=$TEMPORARY_SSH_PASSWORD
}

authenticate_ui_account() {
    local login_path=$1 status error_code mfa_cookie authenticator_type authenticator_id poll_deadline
    local sso_authenticated=false
    : > "$api_cookie"
    chmod 0600 "$api_cookie"
    rm -f -- "$api_csrf" "$api_headers" "$api_response"
    mfa_token=
    spinner_start 'Authenticating UI Account'
    status=$(
        printf '%s\0%s' "$ui_account_password" '' \
            | node -e '
                const fs = require("fs");
                const [password, token = ""] = fs.readFileSync(0).toString().split("\0");
                process.stdout.write(JSON.stringify({username: process.argv[1], password, token}));
              ' "$ui_account" \
            | local_api_request POST "$login_path"
    )
    spinner_stop 'Primary UI Account credentials checked'
    if [[ "$status" != 200 ]]; then
        error_code=$(jq -r '.code // empty' "$api_response" 2>/dev/null || true)
        if [[ "$error_code" == MFA_AUTH_REQUIRED ]]; then
            mfa_cookie=$(jq -er '.data.mfaCookie' "$api_response") \
                || die 'MFA response did not contain a session cookie'
            authenticator_id=$(jq -er '.data.user.default_mfa as $id | .data.authenticators[] | select(.id == $id) | .id' "$api_response") \
                || die 'default MFA authenticator is unavailable'
            authenticator_type=$(jq -er '.data.user.default_mfa as $id | .data.authenticators[] | select(.id == $id) | .type | ascii_upcase' "$api_response") \
                || die 'default MFA authenticator type is unavailable'
            case "$authenticator_type" in
                PUSH)
                    spinner_start 'Sending UniFi Verify push'
                    status=$(
                        printf '%s' "$mfa_cookie" \
                            | node -e '
                                const fs=require("fs");
                                process.stdout.write(JSON.stringify({method:"PUSH",mfaCookie:fs.readFileSync(0,"utf8")}));
                              ' \
                            | local_api_request POST /api/sso/login/mfa/send
                    )
                    require_api_success "$status" 'MFA push request'
                    spinner_stop 'UniFi Verify push sent'
                    mfa_cookie=$(jq -er '.mfaCookie // .data.mfaCookie' "$api_response") \
                        || die 'MFA push response did not contain a polling cookie'
                    spinner_start 'Approve the UniFi Verify push notification'
                    poll_deadline=$((SECONDS + 300))
                    while (( SECONDS < poll_deadline )); do
                        status=$(
                            printf '%s' "$mfa_cookie" \
                                | node -e '
                                    const fs=require("fs");
                                    process.stdout.write(JSON.stringify({mfaCookie:fs.readFileSync(0,"utf8")}));
                                  ' \
                                | local_api_request POST /api/sso/login/mfa/poll
                        )
                        case "$status" in
                            200) sso_authenticated=true; break ;;
                            202) sleep 2 ;;
                            403) die 'MFA push was denied' ;;
                            *) require_api_success "$status" 'MFA push polling' ;;
                        esac
                    done
                    [[ "$sso_authenticated" == true ]] || die 'MFA push approval timed out'
                    spinner_stop 'MFA approved'
                    ;;
                SMS|EMAIL)
                    spinner_start "Sending $authenticator_type verification code"
                    status=$(
                        printf '%s\0%s\0%s' "$authenticator_id" "$authenticator_type" "$mfa_cookie" \
                            | node -e '
                                const fs=require("fs");
                                const [id,method,mfaCookie]=fs.readFileSync(0).toString().split("\0");
                                process.stdout.write(JSON.stringify({id,method,mfaCookie}));
                              ' \
                            | local_api_request POST /api/sso/login/mfa/send
                    )
                    case "$status" in
                        200|201|202|204)
                            spinner_stop "$authenticator_type verification code sent"
                            ;;
                        *)
                            # The UI identity service already sends the code during
                            # the first login step and can reject this explicit
                            # request with VALIDATION_ERROR; use the code it sent.
                            spinner_stop
                            log "$authenticator_type code request returned HTTP $status; enter the code that was already sent."
                            ;;
                    esac
                    ;;
                TOTP|BACKUP_CODE) ;;
                *) die "unsupported MFA authenticator type: $authenticator_type" ;;
            esac
            if [[ "$sso_authenticated" != true ]]; then
                while [[ -z "$mfa_token" ]]; do
                    prompt_secret 'UI Account MFA verification code: ' mfa_token
                    [[ -n "$mfa_token" ]] || log 'The MFA code was empty; please enter it again.'
                done
                spinner_start 'Verifying UI Account MFA'
                status=$(
                    printf '%s\0%s' "$ui_account_password" "$mfa_token" \
                        | node -e '
                            const fs = require("fs");
                            const [password, token = ""] = fs.readFileSync(0).toString().split("\0");
                            process.stdout.write(JSON.stringify({username: process.argv[1], password, token}));
                          ' "$ui_account" \
                        | local_api_request POST "$login_path"
                )
                spinner_stop 'UI Account MFA verified'
            fi
        fi
    fi
    require_api_success "$status" 'UI Account authentication'
    jq -e '.email | type == "string"' "$api_response" >/dev/null \
        || die 'UI Account authentication returned an unexpected response'
}

authenticate_network_controller() {
    local unvr_ip=$controller_ip
    local api_cookie=$controller_api_cookie
    local api_response=$controller_api_response
    local api_headers=$controller_api_headers
    local api_csrf=$controller_api_csrf
    local api_csrf_header=$controller_api_csrf_header
    local mfa_token=
    authenticate_ui_account /api/auth/login
}

configure_ssh_and_updates() {
    local status
    spinner_start "Setting temporary SSH to \"$TEMPORARY_SSH_PASSWORD\" and disabling automatic updates"
    status=$(printf '%s' '{"ssh":{"agreementAccepted":true}}' | local_api_request PATCH /api/system)
    if [[ "$status" == 403 ]]; then
        spinner_clear
        authenticate_ui_account /api/auth/login
        spinner_start "Setting temporary SSH to \"$TEMPORARY_SSH_PASSWORD\" and disabling automatic updates"
        status=$(printf '%s' '{"ssh":{"agreementAccepted":true}}' | local_api_request PATCH /api/system)
    fi
    require_api_success "$status" 'SSH agreement acceptance'
    status=$(
        printf '%s' "$ssh_password" \
            | node -e 'const fs=require("fs"); process.stdout.write(JSON.stringify({password:fs.readFileSync(0,"utf8")}));' \
            | local_api_request POST /api/system/ssh/setpassword
    )
    require_api_success "$status" 'SSH password setup'
    status=$(printf '%s' '{"ssh":{"enabled":true}}' | local_api_request PATCH /api/system)
    require_api_success "$status" 'SSH enablement'
    status=$(printf '%s' '{"schedules":{"firmware":null},"useApplicationSchedules":true}' | local_api_request PATCH /api/system/updates/schedules)
    require_api_success "$status" 'automatic-update disablement'

    for _ in $(seq 1 120); do
        nc -z -G 2 "$unvr_ip" 22 >/dev/null 2>&1 && break
        sleep 2
    done
    nc -z -G 3 "$unvr_ip" 22 >/dev/null 2>&1 || die 'SSH did not become reachable after local setup'
    spinner_stop "Temporary SSH set to \"$TEMPORARY_SSH_PASSWORD\"; automatic updates disabled"
}

disable_update_ssh() {
    local status replacement random
    random=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | shasum -a 256 | awk '{print $1}')
    replacement="DisabledA1${random:0:48}"
    status=$(
        printf '%s' "$replacement" \
            | node -e 'const fs=require("fs"); process.stdout.write(JSON.stringify({password:fs.readFileSync(0,"utf8")}));' \
            | local_api_request POST /api/system/ssh/setpassword
    )
    replacement=
    random=
    case "$status" in 200|201|202|204) ;; *) return 1 ;; esac
    status=$(printf '%s' '{"ssh":{"enabled":false}}' | local_api_request PATCH /api/system)
    case "$status" in 200|201|202|204) ;; *) return 1 ;; esac
    temporary_update_ssh_configured=false
}

resume_setup_bootstrap() {
    local system_json
    system_json=$(public_system) || die 'configured UNVR API is unreachable'
    jq -e '
        ((.deviceState == "setup") or (.deviceState == "updateAvailable")) and
        .cloudConnected == true and
        .name == "UNVR" and
        ((.hardware.shortname // .hardware.shortName // .hardware.model) | type == "string" and test("^UNVR(4)?$"))
    ' <<<"$system_json" >/dev/null \
        || die 'SSH recovery requires the just-configured stock UNVR state'
    if [[ "$timeline_active" != true ]]; then
        print_target_summary
    fi
    timeline_step 1 9 'Resume temporary UNVR setup and enable secure SSH access'
    prompt_bootstrap_credentials
    authenticate_ui_account /api/auth/login
    configure_ssh_and_updates
}

factory_bootstrap() {
    local system_json status sso_user_file deadline timezone attempt setup_accepted=false
    system_json=$(public_system) || die 'factory UNVR setup API is unreachable'
    validate_factory_public_state "$system_json"
    if [[ "$timeline_active" != true ]]; then
        print_target_summary
    fi
    timeline_step 1 9 'Create temporary UNVR ownership and secure SSH access'
    prompt_bootstrap_credentials
    authenticate_ui_account /api/sso/login
    sso_user_file="$temp_root/sso-user.json"
    install -m 0600 "$api_response" "$sso_user_file"

    timezone=$(jq -r '.timezone // "UTC"' <<<"$system_json")
    for attempt in 1 2 3; do
        spinner_start "Creating temporary UNVR owner (attempt $attempt of 3)"
        status=$(
            printf '%s\0%s' "$ui_account_password" "$timezone" \
                | node -e '
                    const fs = require("fs");
                    const ssoUser = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
                    const [password, timezone] = fs.readFileSync(0).toString().split("\0");
                    process.stdout.write(JSON.stringify({
                      name: "UNVR",
                      password,
                      ssoUser,
                      timezone,
                      autoUpdates: {useApplicationSchedules: true, schedules: {firmware: null}},
                      updateFirmware: false,
                      sendDiagnostics: "anonymous",
                      isPrimary: true
                    }));
                  ' "$sso_user_file" \
                | local_api_request POST /api/setup
        )
        if [[ "$status" == 200 || "$status" == 201 || "$status" == 202 || "$status" == 204 ]]; then
            if [[ "$status" == 200 || "$status" == 201 ]]; then
                jq -e '.id | type == "string" and length > 0' "$api_response" >/dev/null \
                    || die 'factory setup did not return the temporary owner'
            fi
            setup_accepted=true
            spinner_stop 'Temporary UNVR owner created and console registered'
            break
        fi
        if [[ "$status" != 000 ]]; then
            require_api_success "$status" 'factory console setup'
        fi
        spinner_clear
        spinner_start 'Checking whether the interrupted setup request completed'
        deadline=$((SECONDS + 45))
        while (( SECONDS < deadline )); do
            system_json=$(public_system 2>/dev/null || true)
            if jq -e '((.deviceState == "setup") or (.deviceState == "updateAvailable")) and .cloudConnected == true' <<<"$system_json" >/dev/null 2>&1; then
                setup_accepted=true
                break
            fi
            sleep 3
        done
        if [[ "$setup_accepted" == true ]]; then
            spinner_stop 'Interrupted setup request completed successfully'
            break
        fi
        jq -e '.deviceState == "notSetup" and .cloudConnected == false' <<<"$system_json" >/dev/null 2>&1 \
            || die 'factory setup connection was interrupted in an ambiguous console state'
        spinner_stop 'Console remained unconfigured; retrying setup safely'
    done
    [[ "$setup_accepted" == true ]] || die 'factory console setup was not accepted after three attempts'

    deadline=$((SECONDS + 600))
    spinner_start 'Waiting for UniFi OS setup to finish'
    while (( SECONDS < deadline )); do
        system_json=$(public_system 2>/dev/null || true)
        if jq -e '((.deviceState == "setup") or (.deviceState == "updateAvailable")) and .cloudConnected == true' <<<"$system_json" >/dev/null 2>&1; then
            break
        fi
        sleep 3
    done
    jq -e '((.deviceState == "setup") or (.deviceState == "updateAvailable")) and .cloudConnected == true' <<<"$system_json" >/dev/null \
        || die 'factory console did not complete cloud setup within ten minutes'
    spinner_stop 'UniFi OS setup complete'

    configure_ssh_and_updates
}

start_master() {
    local fifo="$temp_root/askpass.fifo" helper="$temp_root/askpass.sh" writer ssh_rc
    nc -z -G 3 "$unvr_ip" 22 >/dev/null 2>&1 || die 'SSH port 22 is not reachable'
    rm -f -- "$fifo" || die 'could not clear the private SSH password channel'
    mkfifo -m 600 "$fifo" || die 'could not create the private SSH password channel'
    cat > "$helper" <<'EOF' || die 'could not create the SSH password helper'
#!/bin/bash
set -eu
IFS= read -r answer < "$UNVR_ASKPASS_FIFO"
printf '%s\n' "$answer"
EOF
    chmod 700 "$helper" || die 'could not secure the SSH password helper'
    (
        printf '%s\n' "$ssh_password" > "$fifo"
    ) &
    writer=$!
    askpass_writer_pid=$writer
    if DISPLAY=unvr-installer \
    SSH_ASKPASS="$helper" \
    SSH_ASKPASS_REQUIRE=force \
    UNVR_ASKPASS_FIFO="$fifo" \
    ssh \
        -M -S "$control_socket" -fNT \
        -o ControlPersist=3600 \
        -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=6 \
        -o NumberOfPasswordPrompts=1 \
        -o PreferredAuthentications=keyboard-interactive,password \
        -o PubkeyAuthentication=no \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$known_hosts" \
        -o LogLevel=ERROR \
        "root@$unvr_ip"; then
        ssh_rc=0
    else
        ssh_rc=$?
    fi
    if kill -0 "$writer" >/dev/null 2>&1; then
        kill "$writer" >/dev/null 2>&1 || true
    fi
    wait "$writer" >/dev/null 2>&1 || true
    askpass_writer_pid=
    rm -f -- "$fifo" "$helper" || die 'could not remove the SSH password helper'
    [[ "$ssh_rc" -eq 0 ]] || return "$ssh_rc"
    ssh -S "$control_socket" -O check "root@$unvr_ip" >/dev/null 2>&1 || die 'SSH ControlMaster did not start'
}

remote_phase() {
    local phase=$1
    shift
    ssh -S "$control_socket" -o BatchMode=yes "root@$unvr_ip" /bin/bash -s -- "$phase" "$@" < "$remote_engine"
}

phase_failure() {
    local label=$1 output_file=$2 detail
    spinner_clear
    detail=$(awk '/ERROR:|[Ee]rror:|[Ff]ailed/{line=$0} END{print line}' "$output_file" 2>/dev/null || true)
    [[ -n "$detail" ]] || detail=$(awk 'NF{line=$0} END{print line}' "$output_file" 2>/dev/null || true)
    detail=$(printf '%s' "$detail" | tr '\r\n' '  ' | sed 's/[[:space:]][[:space:]]*/ /g' | cut -c1-220)
    if [[ -n "$detail" ]]; then
        die "$label: $detail"
    fi
    die "$label"
}

quiet_remote_phase() {
    local label=$1 output_file="$temp_root/phase-output.log" rc
    shift
    : > "$output_file"
    spinner_start "$label"
    set +e
    remote_phase "$@" > "$output_file" 2>&1
    rc=$?
    set -e
    if [[ "$rc" -ne 0 && "$interrupt_declined" == true ]]; then
        interrupt_declined=false
        quiet_remote_phase "$label" "$@"
        return
    fi
    [[ "$rc" -eq 0 ]] || phase_failure "$label failed" "$output_file"
    spinner_stop "$label"
}

quiet_local_step() {
    local label=$1 output_file="$temp_root/phase-output.log" rc
    shift
    : > "$output_file"
    spinner_start "$label"
    set +e
    "$@" > "$output_file" 2>&1
    rc=$?
    set -e
    if [[ "$rc" -ne 0 && "$interrupt_declined" == true ]]; then
        interrupt_declined=false
        quiet_local_step "$label" "$@"
        return
    fi
    [[ "$rc" -eq 0 ]] || phase_failure "$label failed" "$output_file"
    spinner_stop "$label"
}

capture_remote_phase() {
    local label=$1 output_file="$temp_root/phase-output.log" rc
    shift
    : > "$output_file"
    captured_output=
    spinner_start "$label"
    set +e
    captured_output=$(remote_phase "$@" 2> "$output_file")
    rc=$?
    set -e
    if [[ "$rc" -ne 0 && "$interrupt_declined" == true ]]; then
        interrupt_declined=false
        capture_remote_phase "$label" "$@"
        return
    fi
    [[ "$rc" -eq 0 ]] || phase_failure "$label failed" "$output_file"
    spinner_stop "$label"
}

capture_local_step() {
    local label=$1 output_file="$temp_root/phase-output.log" rc
    shift
    : > "$output_file"
    captured_output=
    spinner_start "$label"
    set +e
    captured_output=$("$@" 2> "$output_file")
    rc=$?
    set -e
    if [[ "$rc" -ne 0 && "$interrupt_declined" == true ]]; then
        interrupt_declined=false
        capture_local_step "$label" "$@"
        return
    fi
    [[ "$rc" -eq 0 ]] || phase_failure "$label failed" "$output_file"
    spinner_stop "$label"
}

unas_setup_is_complete() {
    # Configured consoles redact isSetup from the unauthenticated response.
    # deviceState is the native setup-state signal, not SSH/cloud availability.
    jq -e '
        type == "object" and
        .hardware.shortname == "UNASPRO" and
        (.deviceState == "setup" or .deviceState == "updateAvailable") and
        ((has("isSetup") | not) or .isSetup == true)
    ' <<<"$1" >/dev/null 2>&1
}

show_unas_setup_checkpoint() {
    local notice=${1:-}
    spinner_clear
    if [[ -t 1 && ${TERM:-dumb} != dumb && "$timeline_dashboard_drawn" == true &&
          "$timeline_header_rewrite_safe" == true ]]; then
        printf '\r\033[%dA\033[J' "$((timeline_dashboard_rows + setup_checkpoint_rows))"
    fi
    timeline_dashboard_drawn=false
    printf '\n'
    print_box_border '┌' '┐'
    reset_box_heading 'Complete UNAS Pro setup'
    reset_box_line "Open https://$unvr_ip or use the UniFi mobile app."
    reset_box_line 'Finish console setup, then return here and press Enter.'
    reset_box_line 'You can leave storage-pool creation for later in UniFi Drive.'
    if [[ -n "$notice" ]]; then
        reset_box_line ''
        reset_box_colored_heading 33 "$notice"
    fi
    print_box_border '└' '┘'
    # Six box rows, plus the blank rows above it and above the dashboard.
    setup_checkpoint_rows=8
    [[ -z "$notice" ]] || setup_checkpoint_rows=10
    if [[ "$timeline_active" == true ]]; then
        timeline_header_rewrite_safe=true
        timeline_render_dashboard
    fi
}

hide_unas_setup_checkpoint() {
    if [[ -t 1 && ${TERM:-dumb} != dumb && "$setup_checkpoint_rows" -gt 0 &&
          "$timeline_dashboard_drawn" == true && "$timeline_header_rewrite_safe" == true ]]; then
        printf '\r\033[%dA\033[J' "$((timeline_dashboard_rows + setup_checkpoint_rows))"
        timeline_dashboard_drawn=false
        timeline_render_dashboard
    fi
    setup_checkpoint_rows=0
}

wait_for_user_unas_setup() {
    local setup_confirmation system notice=''
    while :; do
        show_unas_setup_checkpoint "$notice"
        prompt_value 'Press Enter to continue: ' setup_confirmation \
            || die 'input closed before UNAS setup could be verified'
        spinner_start 'Verifying completed UNAS setup'
        system=$(public_system 2>/dev/null || true)
        if unas_setup_is_complete "$system"; then
            spinner_stop 'Verified completed UNAS setup'
            hide_unas_setup_checkpoint
            return 0
        fi
        spinner_clear
        if jq -e 'type == "object" and .hardware.shortname == "UNASPRO"' \
            <<<"$system" >/dev/null 2>&1; then
            notice='Setup is not complete yet. Finish setup, then press Enter again.'
        else
            notice='Cannot verify the console. Check its connection, then try again.'
        fi
    done
}

completion_banner() {
    timeline_complete_current
    printf '\n\033[1;32m✓  CONVERSION COMPLETE! Your UNVR is now a UNAS Pro!\033[0m\n\n'
    print_box_border '┌' '┐'
    reset_box_line "UNAS setup verified at https://$unvr_ip"
    reset_box_line 'Manage your storage pools and shares in UniFi Drive.'
    print_box_border '└' '┘'
}

stage_file() {
    local source=$1 remote_name=$2 expected_hash=$3 actual source_size required_kib
    [[ "$remote_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die 'invalid remote artifact name'
    [[ "$expected_hash" =~ ^[0-9a-f]{64}$ ]] || die "invalid expected artifact hash: $remote_name"
    [[ -f "$source" && ! -L "$source" ]] || die "local staged artifact is missing or unsafe: $remote_name"
    actual=$(sha "$source")
    [[ "$actual" == "$expected_hash" ]] || die "local staged artifact hash mismatch: $remote_name"
    source_size=$(stat -f '%z' "$source")
    [[ "$source_size" =~ ^[0-9]+$ ]] || die "local staged artifact size is invalid: $remote_name"
    required_kib=$((source_size / 1024 + 131072))
    ssh -S "$control_socket" -o BatchMode=yes "root@$unvr_ip" \
        "set -eu; install -d -m 700 /data/unvr-unas-installer; available=\$(df -Pk /data/unvr-unas-installer | awk 'NR == 2 {print \$4}'); test \"\$available\" -ge '$required_kib' || { echo 'ERROR: insufficient target space for staged artifact' >&2; exit 1; }; umask 077; final=/data/unvr-unas-installer/$remote_name; part=\"\$final.part.\$\$\"; trap 'rm -f -- \"\$part\"' EXIT HUP INT TERM; cat > \"\$part\"; test \"\$(sha256sum \"\$part\" | awk '{print \$1}')\" = '$expected_hash'; chmod 600 \"\$part\"; mv -f \"\$part\" \"\$final\"; trap - EXIT HUP INT TERM" \
        < "$source"
}

# Place byte-identical prebuilt modules where the remote modules phase looks for
# them, so it verifies their pinned hashes and vermagic instead of compiling.
stage_prebuilt_modules() {
    local target=/data/unvr-unas-runtime/modules/4.19.152-alpine-unvr name pin expected
    for name in zstd_compress.ko btrfs.ko fuse.ko; do
        case "$name" in
            zstd_compress.ko) pin=ZSTD_MODULE_HASH ;;
            btrfs.ko) pin=BTRFS_MODULE_HASH ;;
            fuse.ko) pin=FUSE_MODULE_HASH ;;
        esac
        expected=$(sed -n "s/^readonly $pin=//p" "$remote_engine")
        [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || die "remote engine pin is missing: $pin"
        [[ -f "$prebuilt_modules/$name" && ! -L "$prebuilt_modules/$name" ]] || die "prebuilt module is missing: $name"
        [[ "$(sha "$prebuilt_modules/$name")" == "$expected" ]] || die "prebuilt module is not the validated build: $name"
        ssh -S "$control_socket" -o BatchMode=yes "root@$unvr_ip" \
            "set -eu; install -d -m 755 '$target'; cat > '$target/.$name.tmp'; chmod 644 '$target/.$name.tmp'; test \"\$(sha256sum '$target/.$name.tmp' | cut -d' ' -f1)\" = '$expected'; mv -f '$target/.$name.tmp' '$target/$name'" \
            < "$prebuilt_modules/$name" || die "could not stage prebuilt module: $name"
    done
}

prepare_update_profiles() {
    local output_dir="$temp_root/update-profiles" output bundle expected_bundle expected_hash actual_hash args=()
    [[ -z "$unvr5_firmware" ]] || args+=(--unvr-5 "$unvr5_firmware")
    [[ -z "$unas5_firmware" ]] || args+=(--unas-5 "$unas5_firmware")
    [[ -z "$artifact_cache" ]] || args+=(--artifact-cache "$artifact_cache")
    if [[ ${#args[@]} -gt 0 ]]; then
        output=$("$profile_builder" "$output_dir" "${args[@]}")
    else
        output=$("$profile_builder" "$output_dir")
    fi
    bundle="$output_dir/unvr-unas-update-profiles.tar.gz"
    expected_bundle=$(printf '%s\n' "$output" | sed -n 's/^PROFILE_BUNDLE=//p')
    expected_hash=$(printf '%s\n' "$output" | sed -n 's/^PROFILE_BUNDLE_SHA256=//p')
    [[ -f "$bundle" && ! -L "$bundle" ]] || {
        printf 'ERROR: profile builder completed without its deterministic bundle\n' >&2
        return 1
    }
    [[ "$expected_bundle" == "$bundle" && "$expected_hash" =~ ^[0-9a-f]{64}$ ]] || {
        printf 'ERROR: profile builder output contract is incomplete\n' >&2
        return 1
    }
    actual_hash=$(sha "$bundle")
    [[ "$actual_hash" == "$expected_hash" ]] || {
        printf 'ERROR: profile builder output hash does not match its bundle\n' >&2
        return 1
    }
    printf '%s\n' "$output"
}

wait_for_reboot() {
    local deadline was_down=false
    spinner_start 'Waiting for UNVR to reboot and return over SSH'
    ssh -S "$control_socket" -O exit "root@$unvr_ip" >/dev/null 2>&1 || true
    rm -f -- "$control_socket"
    deadline=$((SECONDS + 180))
    while (( SECONDS < deadline )); do
        if ! nc -z -G 2 "$unvr_ip" 22 >/dev/null 2>&1; then was_down=true; break; fi
        sleep 2
    done
    [[ "$was_down" == true ]] || die 'UNVR did not go offline for reboot'
    deadline=$((SECONDS + 600))
    while (( SECONDS < deadline )); do
        if nc -z -G 2 "$unvr_ip" 22 >/dev/null 2>&1; then
            sleep 5
            if start_master >/dev/null 2>&1; then
                spinner_stop 'UNVR rebooted and SSH returned'
                return
            fi
        fi
        sleep 5
    done
    die 'UNVR SSH did not return within ten minutes'
}

prepare_original_controller_cleanup() {
    local association gateway controller_system status sites site endpoint matched=false
    local matching_site_count=0 matched_site= deadline authenticated_again=false
    if [[ "$skip_controller_cleanup" == true ]]; then
        controller_cleanup_mode=unavailable
        log 'Skipped optional Network controller discovery because --skip-controller-cleanup was given.'
        return
    fi
    capture_remote_phase 'Saved the original UniFi Network attachment' \
        factory-network-association "$unvr_ip"
    association=$captured_output
    controller_client_mac=$(printf '%s\n' "$association" | sed -n 's/^CLIENT_MAC=//p')
    gateway=$(printf '%s\n' "$association" | sed -n 's/^GATEWAY_IP=//p')
    [[ "$controller_client_mac" =~ ^[0-9a-f]{2}(:[0-9a-f]{2}){5}$ ]] \
        || die 'could not capture the exact UNVR client record for controller cleanup'
    validate_ipv4 "$gateway" || die 'could not capture the UNVR gateway for controller discovery'
    if [[ -z "$controller_ip" ]]; then
        controller_ip=$gateway
    fi
    validate_ipv4 "$controller_ip" || die 'the discovered UniFi Network controller address is invalid'
    [[ "$controller_ip" != "$unvr_ip" ]] || die 'the discovered Network controller resolves to the UNVR itself'

    controller_system=$(curl -ksS --connect-timeout 5 --max-time 20 \
        "https://$controller_ip/api/system" 2>/dev/null || true)
    jq -e '
        (.deviceState == "setup" or .deviceState == "updateAvailable") and
        ((.hardware.shortname // .hardware.shortName // .hardware.model) |
            type == "string" and length > 0 and test("^(UNVR|UNAS)"; "i") | not)
    ' <<<"$controller_system" >/dev/null 2>&1 \
        || die 'could not verify the original UniFi Network controller; rerun with --controller-ip if it is not the UNVR gateway'

    authenticate_network_controller
    spinner_start 'Locating the exact UNVR client record on its original Network site'
    sites=
    deadline=$((SECONDS + 300))
    while (( SECONDS < deadline )); do
        status=$(printf '' | controller_api_request GET /proxy/network/api/self/sites)
        case "$status" in
            200|201|202|204)
                sites=$(jq -r '
                    if (.data | type) == "array" then .data[]?
                    elif (.data.sites | type) == "array" then .data.sites[]?
                    elif type == "array" then .[]?
                    else empty
                    end | .name // .id // empty
                ' "$controller_api_response" 2>/dev/null || true)
                [[ -z "$sites" ]] || break
                ;;
            401|403)
                if [[ "$authenticated_again" == false ]]; then
                    spinner_clear
                    authenticate_network_controller
                    authenticated_again=true
                    spinner_start 'Waiting for the original Network application and site list'
                fi
                ;;
            000|502|503|504) ;;
            *) require_controller_api_success "$status" 'Network site discovery' ;;
        esac
        sleep 5
    done
    if [[ -z "$sites" ]]; then
        controller_cleanup_mode=unavailable
        spinner_stop 'Network sites remained unavailable; skipped optional stale-client cleanup'
        return
    fi
    while IFS= read -r site; do
        [[ "$site" =~ ^[A-Za-z0-9_-]+$ ]] || die 'the controller returned an unsafe Network site identifier'
        matched=false
        for endpoint in stat/sta rest/user; do
            status=$(printf '' | controller_api_request GET \
                "/proxy/network/api/s/$site/$endpoint/$controller_client_mac")
            if [[ "$status" == 200 ]] && jq -e --arg mac "$controller_client_mac" --arg ip "$unvr_ip" '
                .data | any(
                    (((.mac // "") | ascii_downcase) == $mac) and
                    ((.ip // "") == $ip)
                )
            ' "$controller_api_response" >/dev/null 2>&1; then
                matched=true
                break
            fi
        done
        if [[ "$matched" == true ]]; then
            matching_site_count=$((matching_site_count + 1))
            matched_site=$site
        fi
    done <<<"$sites"
    if [[ "$matching_site_count" -eq 0 ]]; then
        controller_cleanup_mode=not-present
        spinner_stop 'No stale UNVR client record was present on an accessible Network site'
        return
    fi
    [[ "$matching_site_count" -eq 1 ]] \
        || die 'the exact UNVR client record appeared on more than one Network site'
    controller_site=$matched_site
    controller_cleanup_mode=exact
    spinner_stop 'Saved the exact original Network site and client record'
}

unregister_prior_console_site() {
    quiet_remote_phase 'Unregistered the old UNVR console from Site Manager' factory-cloud-unregister
}

forget_prior_network_client() {
    local status payload verify_status attempt
    case "$controller_cleanup_mode" in
        unavailable|not-present)
            log 'Skipped optional Network client cleanup because no exact accessible stale record was available.'
            return
            ;;
        exact) ;;
        *) die 'the Network-controller cleanup state is unresolved' ;;
    esac
    [[ -n "$controller_ip" && -n "$controller_site" && -n "$controller_client_mac" ]] \
        || die 'the saved Network-controller cleanup boundary is incomplete'
    payload=$(jq -nc --arg mac "$controller_client_mac" '{cmd:"forget-sta",macs:[$mac]}')
    spinner_start 'Removing the stale offline UNVR record from the original Network controller'
    for attempt in 1 2 3; do
        status=$(printf '%s' "$payload" | controller_api_request POST \
            "/proxy/network/api/s/$controller_site/cmd/stamgr")
        if [[ "$status" == 401 || "$status" == 403 ]]; then
            spinner_clear
            authenticate_network_controller
            spinner_start 'Removing the stale offline UNVR record from the original Network controller'
            continue
        fi
        require_controller_api_success "$status" 'stale UNVR Network-client removal'
        jq -e '.meta.rc == "ok"' "$controller_api_response" >/dev/null 2>&1 \
            || die 'the Network controller did not accept the exact-client forget operation'
        sleep 2
        verify_status=$(printf '' | controller_api_request GET \
            "/proxy/network/api/s/$controller_site/rest/user/$controller_client_mac")
        if [[ "$verify_status" == 404 ]] || {
            [[ "$verify_status" == 200 ]] &&
            jq -e '(.data // []) | length == 0' "$controller_api_response" >/dev/null 2>&1
        }; then
            spinner_stop 'Removed the stale offline UNVR record from the original Network controller'
            return
        fi
    done
    die 'the stale UNVR client record remained on the original Network controller'
}

validate_controller_unas_identity() {
    local status endpoint deadline authenticated_again=false
    if [[ "$controller_cleanup_mode" != exact ]]; then
        log 'Skipped optional Network client enrichment; authoritative local UNAS Pro setup validation passed.'
        return
    fi
    spinner_start 'Waiting for the Network controller UNAS Pro record'
    deadline=$((SECONDS + 30))
    while (( SECONDS < deadline )); do
        for endpoint in stat/sta rest/user; do
            status=$(printf '' | controller_api_request GET \
                "/proxy/network/api/s/$controller_site/$endpoint/$controller_client_mac")
            if [[ "$status" == 401 || "$status" == 403 ]] && [[ "$authenticated_again" == false ]]; then
                spinner_clear
                authenticate_network_controller
                authenticated_again=true
                spinner_start 'Waiting for the Network controller UNAS Pro record'
                continue
            fi
            if [[ "$status" == 200 ]] && jq -e --arg mac "$controller_client_mac" --arg ip "$unvr_ip" '
                .data | any(
                    (((.mac // "") | ascii_downcase) == $mac) and
                    ((.ip // .last_ip // "") == $ip) and
                    ((.unifi_device_info_from_ucore // {}) as $ucore |
                        ((($ucore.product_line // "") | ascii_downcase) == "drive") and
                        (($ucore.product_model // "") == "UNAS Pro") and
                        (($ucore.product_shortname // "") == "UNASPRO") and
                        (($ucore.fw_version // "") == "5.1.33") and
                        (($ucore.ucore_device_status // "") == "online") and
                        ($ucore.managed == false)
                    )
                )
            ' "$controller_api_response" >/dev/null 2>&1; then
                spinner_stop 'Network controller recognized the unmanaged UNAS Pro'
                return
            fi
        done
        sleep 2
    done
    spinner_clear
    timeline_complete_current
    log 'Network client enrichment has not arrived yet; authoritative local UNAS Pro setup validation passed.'
}

wait_for_factory_reset() {
    local deadline was_down=false system_json
    spinner_start 'Waiting for the destructive factory reset to complete'
    if [[ -S "$control_socket" ]]; then
        ssh -S "$control_socket" -O exit "root@$unvr_ip" >/dev/null 2>&1 || true
    fi
    rm -f -- "$control_socket"
    deadline=$((SECONDS + 240))
    while (( SECONDS < deadline )); do
        if ! nc -z -G 2 "$unvr_ip" 22 >/dev/null 2>&1 &&
           ! nc -z -G 2 "$unvr_ip" 443 >/dev/null 2>&1; then
            was_down=true
            break
        fi
        sleep 2
    done
    [[ "$was_down" == true ]] || die 'UNVR did not go offline for the destructive factory reset'
    spinner_clear
    forget_prior_network_client
    spinner_start 'Waiting for the destructive factory reset to complete'
    deadline=$((SECONDS + 900))
    while (( SECONDS < deadline )); do
        system_json=$(public_system 2>/dev/null || true)
        if jq -e '
            .deviceState == "notSetup" and
            .cloudConnected == false and
            .name == "UNVR" and
            ((.hardware.shortname // .hardware.shortName // .hardware.model) | test("^UNVR(4)?$"))
        ' <<<"$system_json" >/dev/null 2>&1; then
            validate_factory_public_state "$system_json"
            : > "$api_cookie"
            : > "$known_hosts"
            chmod 0600 "$known_hosts"
            rm -f -- "$api_csrf" "$api_headers" "$api_response" "$api_csrf_header"
            mfa_token=
            spinner_stop 'Factory reset and external-storage erase completed'
            return
        fi
        sleep 5
    done
    die 'UNVR did not return to an unconfigured factory state within fifteen minutes'
}

confirm_destructive_reset() {
    local confirmation
    print_conversion_title
    print_destructive_reset_box
    while :; do
        prompt_value 'Continue with the destructive reset? [y/N] ' confirmation
        case "$confirmation" in
            y|Y|yes|YES|Yes)
                if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
                    printf '\033[H\033[2J\033[3J'
                    print_conversion_title
                fi
                return
                ;;
            ''|n|N|no|NO|No) log 'Destructive reset cancelled; no changes were made.'; exit 0 ;;
            *) printf 'Please answer yes or no.\n' ;;
        esac
    done
}

ensure_reset_ssh_access() {
    local system_json=$1 state master_ready=false master_rc=1
    state=$(jq -r '.deviceState // "unavailable"' <<<"$system_json" 2>/dev/null || printf unavailable)
    case "$state" in
        notSetup)
            if jq -e '
                .name == "UNVR" and
                ((.hardware.shortname // .hardware.shortName // .hardware.model) | test("^UNVR(4)?$"))
            ' <<<"$system_json" >/dev/null 2>&1; then
                factory_bootstrap
            elif jq -e '
                .name == "UNAS Pro" and
                ((.hardware.shortname // .hardware.shortName // .hardware.model) == "UNASPRO")
            ' <<<"$system_json" >/dev/null 2>&1; then
                if [[ "$timeline_active" != true ]]; then
                    print_target_summary
                fi
                timeline_step 1 9 'Connect to the existing logical UNAS retry state'
                prompt_bootstrap_credentials
                nc -z -G 3 "$unvr_ip" 22 >/dev/null 2>&1 \
                    || die 'logical UNAS retry requires the temporary SSH access left by this installer; factory-reset this older conversion first'
            else
                die 'unconfigured console identity is neither a stock UNVR nor this installer logical UNAS retry state'
            fi
            ;;
        setup|updateAvailable)
            if [[ "$timeline_active" != true ]]; then
                print_target_summary
            fi
            timeline_step 1 9 'Connect to the existing temporary UNVR owner'
            prompt_bootstrap_credentials
            if nc -z -G 3 "$unvr_ip" 22 >/dev/null 2>&1; then
                spinner_start 'Checking existing temporary SSH access'
                if start_master >/dev/null 2>&1; then
                    master_rc=0
                else
                    master_rc=$?
                fi
                spinner_stop
            fi
            if [[ "$master_rc" -eq 0 ]]; then
                master_ready=true
                spinner_start "Reusing temporary SSH password \"$TEMPORARY_SSH_PASSWORD\""
                spinner_stop
            else
                rm -f -- "$control_socket"
                authenticate_ui_account /api/auth/login
                configure_ssh_and_updates
            fi
            ;;
        *) die 'console must be locally reachable and either configured or at the factory setup screen before reset' ;;
    esac
    if [[ "$master_ready" == false ]]; then
        spinner_start 'Establishing the reset SSH session'
        start_master
        spinner_stop 'Reset SSH session established'
    else
        spinner_start 'Using the existing reset SSH session'
        spinner_stop 'Reset SSH session established'
    fi
}

run_destructive_factory_reset() {
    local system_json=$1 reset_output reset_rc drive_count
    confirm_destructive_reset
    ensure_reset_ssh_access "$system_json"
    capture_remote_phase 'Validated the physical UNVR and destructive reset boundary' factory-reset-preflight
    drive_count=$(printf '%s\n' "$captured_output" | sed -n 's/^SATA_DRIVE_COUNT=//p')
    [[ "$drive_count" =~ ^[0-4]$ ]] || die 'factory-reset preflight did not report the installed drive count'
    # After the reset UniFi OS builds a Protect pool on every installed drive.
    # The storage classifier only recognizes the single-drive pool in bay 1,
    # so with more drives the conversion would stop after the reset.
    (( drive_count <= 1 )) || die "$drive_count drives are installed. Remove all drives (or keep only bay 1), rerun, and insert the others after UNAS setup to create the pool in UniFi Drive."
    prepare_original_controller_cleanup
    unregister_prior_console_site
    spinner_start 'Erasing all installed drive data and factory-resetting the UNVR'
    set +e
    reset_output=$(remote_phase factory-reset-wipe 2>&1)
    reset_rc=$?
    set -e
    spinner_clear
    if [[ "$reset_rc" -ne 0 && "$reset_rc" -ne 255 && "$interrupt_declined" == true ]]; then
        interrupt_declined=false
        reset_rc=255
    fi
    [[ "$reset_rc" -eq 0 || "$reset_rc" -eq 255 ]] \
        || die "stock Ubiquiti destructive reset failed: $reset_output"
    wait_for_factory_reset
}

run_install_5x() {
    timeline_step 2 9 'Verify signed UNVR 5.1.33 baseline and storage-preservation state'
    quiet_remote_phase 'Validated firmware, hardware and resume state' preflight-5x
    if [[ "$dry_run" == true ]]; then
        quiet_remote_phase 'Validated the storage-preservation gate without changes' disk-preflight-clean-5x
        log 'dry-run complete: no target or local persistent state was changed'
        return
    fi

    local profile_output profile_bundle profile_hash disk_info factory_pool_token
    local factory_pool_needs_erase=false recreated_pool_needs_erase=false
    local reboot_rc reboot_output
    timeline_step 3 9 'Build the hash-verified official UNAS compatibility payload'
    capture_local_step 'Built and verified the official compatibility payload' prepare_update_profiles
    profile_output=$captured_output
    profile_bundle=$(printf '%s\n' "$profile_output" | sed -n 's/^PROFILE_BUNDLE=//p')
    profile_hash=$(printf '%s\n' "$profile_output" | sed -n 's/^PROFILE_BUNDLE_SHA256=//p')
    [[ -f "$profile_bundle" && "$profile_hash" =~ ^[0-9a-f]{64}$ ]] \
        || die 'profile builder did not return a valid bundle'

    capture_remote_phase 'Classified and locked the storage state safely' lock-clean-disk-5x
    disk_info=$captured_output
    printf '%s\n' "$disk_info" | grep -q '^DISK_TOKEN=' \
        || die 'the zero-to-four-drive topology could not be locked safely'
    factory_pool_token=$(printf '%s\n' "$disk_info" | sed -n 's/^DISK_TOKEN=//p')
    if printf '%s\n' "$disk_info" | grep -qx 'FACTORY_POOL_NEEDS_ERASE=1'; then
        factory_pool_needs_erase=true
    fi
    if printf '%s\n' "$disk_info" | grep -qx 'RECREATED_POOL_NEEDS_ERASE=1'; then
        recreated_pool_needs_erase=true
    fi
    timeline_step 4 9 'Capture rollback state and install safety guards'
    quiet_remote_phase 'Verified the rollback backup' backup-5x
    quiet_remote_phase 'Applied the update safety guard' update-guard
    quiet_remote_phase 'Applied the dedicated-NAS service guard' dedicated-guard
    timeline_step 5 9 'Build exact native Btrfs, Zstd and FUSE modules'
    quiet_local_step 'Uploaded the immutable build and compatibility payload' stage_file "$profile_bundle" update-profiles.tar.gz "$profile_hash"
    if [[ -n "$prebuilt_modules" ]]; then
        quiet_local_step 'Staged the prebuilt, hash-pinned Btrfs, Zstd and FUSE modules' stage_prebuilt_modules
    fi
    quiet_remote_phase 'Verified native Btrfs, Zstd and FUSE modules' modules "$profile_hash"
    if [[ "$factory_pool_needs_erase" == true ]]; then
        quiet_remote_phase 'Returned slot 1 to a blank onboarding state' erase-factory-pool-5x "$factory_pool_token"
        capture_remote_phase 'Revalidated blank slot-1 storage' disk-preflight-clean-5x
        disk_info=$captured_output
        printf '%s\n' "$disk_info" | grep -qx 'DISK_STATE=blank' \
            || die 'slot 1 did not remain blank after factory-pool cleanup'
    elif [[ "$recreated_pool_needs_erase" == true ]]; then
        quiet_remote_phase 'Removed the interrupted empty storage pool' erase-recreated-pool-5x "$factory_pool_token"
        capture_remote_phase 'Revalidated blank slot-1 storage' disk-preflight-clean-5x
        disk_info=$captured_output
        printf '%s\n' "$disk_info" | grep -qx 'DISK_STATE=blank' \
            || die 'slot 1 did not remain blank after interrupted-pool cleanup'
    fi
    timeline_step 6 9 'Install scoped UNAS Pro identity and official Drive userspace'
    quiet_remote_phase 'Installed and verified the scoped UNAS Pro identity' direct-5x-profile "$profile_hash"
    quiet_remote_phase 'Installed and verified official UniFi Drive 4.3.10' direct-5x-packages
    timeline_step 7 9 'Verify UNAS services while preserving installed storage'
    quiet_remote_phase 'Verified the UNAS pre-storage state' prestorage-5x

    timeline_step 8 9 'Reboot and run pre-storage health validation'
    set +e
    reboot_output=$(remote_phase reboot)
    reboot_rc=$?
    set -e
    if [[ "$reboot_rc" -ne 0 && "$reboot_rc" -ne 255 && "$interrupt_declined" == true ]]; then
        interrupt_declined=false
        reboot_rc=255
    fi
    [[ "$reboot_rc" -eq 0 || "$reboot_rc" -eq 255 ]] || die 'unexpected failure while requesting reboot'
    if ! printf '%s\n' "$reboot_output" | grep -qx 'REBOOT_ALREADY_COMPLETE=1'; then
        wait_for_reboot
    else
        spinner_start 'Using the completed post-install reboot'
        spinner_stop 'Completed post-install reboot detected'
    fi
    quiet_remote_phase 'Validated UNAS services and preserved storage after reboot' validate-prestorage-5x
    timeline_step 9 9 'Complete official UNAS setup and verify the handoff'
    quiet_remote_phase 'Prepared the official UNAS Pro setup flow' logical-unadopt
    set +e
    reboot_output=$(remote_phase handoff-reboot)
    reboot_rc=$?
    set -e
    if [[ "$reboot_rc" -ne 0 && "$reboot_rc" -ne 255 && "$interrupt_declined" == true ]]; then
        interrupt_declined=false
        reboot_rc=255
    fi
    [[ "$reboot_rc" -eq 0 || "$reboot_rc" -eq 255 ]] || die 'unexpected failure while requesting the UNAS handoff reboot'
    if ! printf '%s\n' "$reboot_output" | grep -qx 'HANDOFF_REBOOT_ALREADY_COMPLETE=1'; then
        wait_for_reboot
    fi
    quiet_remote_phase 'Validated unmanaged UNAS Pro discovery and local setup' validate-unadopted-handoff-5x
    validate_controller_unas_identity
    wait_for_user_unas_setup
    completion_banner
}

run_normalize_to_5x() {
    local normalize_rc normalize_output
    timeline_step 2 9 'Verify signed UNVR 5.1.33 baseline and storage-preservation state'
    quiet_remote_phase 'Validated the source firmware for normalization' normalization-preflight
    if [[ "$dry_run" == true ]]; then
        log 'dry-run: source is eligible for stock signed normalization to 5.1.33'
        log 'dry-run complete: no firmware was downloaded, staged or written'
        return
    fi
    quiet_remote_phase 'Downloaded signed UNVR 5.1.33 directly to the console' normalization-image-stage
    quiet_remote_phase 'Verified firmware with the stock Ubiquiti updater' normalization-image-check
    spinner_start 'Applying signed UNVR 5.1.33 through the stock updater'
    set +e
    normalize_output=$(remote_phase normalize-to-5x 2>&1)
    normalize_rc=$?
    set -e
    spinner_clear
    if [[ "$normalize_rc" -ne 0 && "$normalize_rc" -ne 255 && "$interrupt_declined" == true ]]; then
        interrupt_declined=false
        normalize_rc=255
    fi
    [[ "$normalize_rc" -eq 0 || "$normalize_rc" -eq 255 ]] \
        || die "stock firmware normalization failed: $normalize_output"
    wait_for_reboot
    quiet_remote_phase 'Validated exact 5.1.33 after normalization' preflight-5x
    run_install_5x
}

run_install() {
    local baseline
    baseline=$(remote_phase detect-baseline)
    case "$baseline" in
        BASELINE=5.1.33) run_install_5x ;;
        BASELINE=normalization-required) run_normalize_to_5x ;;
        *) die "unsupported UNVR baseline: $baseline" ;;
    esac
}

run_status() {
    remote_phase status
}

run_rollback() {
    local confirmation
    printf 'Rollback restores software/configuration but preserves the SATA pool and all data.\n'
    prompt_value 'Type exactly "ROLL BACK UNVR SOFTWARE": ' confirmation
    [[ "$confirmation" == 'ROLL BACK UNVR SOFTWARE' ]] || die 'rollback was not confirmed'
    remote_phase rollback
}

run_unadopt() {
    local confirmation
    printf 'This unregisters the console from UniFi cloud and clears its ULP owner so it can be adopted again as UNASPRO.\n'
    printf 'The SATA storage pool is not formatted or modified. A guarded local backup is created first.\n'
    prompt_value 'Type exactly "UNREGISTER AND READOPT AS UNAS": ' confirmation
    [[ "$confirmation" == 'UNREGISTER AND READOPT AS UNAS' ]] || die 'logical UNAS unadoption was not confirmed'
    remote_phase logical-unadopt
    log 'Site Manager should offer a transient Setup and Merge prompt while this Mac is on the same LAN.'
    log 'The unregistered console will not become a persistent Site Manager card until setup registers it to the owner account.'
    log 'If the prompt is dismissed, use a fresh Site Manager session or complete setup at the local URL; the resulting UNAS console can then be merged.'
    log "UNASPRO adoption is ready at https://$unvr_ip"
}

parse_args "$@"
temp_root=$(mktemp -d /private/tmp/unvr-unas-installer.XXXXXX)
materialize_embedded_helpers
check_macos
control_socket="$temp_root/ssh.sock"
known_hosts="$temp_root/known_hosts"
api_cookie="$temp_root/api-cookies"
api_response="$temp_root/api-response.json"
api_headers="$temp_root/api-response.headers"
api_csrf="$temp_root/api-csrf-token"
api_csrf_header="$temp_root/api-csrf-header"
controller_api_cookie="$temp_root/controller-api-cookies"
controller_api_response="$temp_root/controller-api-response.json"
controller_api_headers="$temp_root/controller-api-response.headers"
controller_api_csrf="$temp_root/controller-api-csrf-token"
controller_api_csrf_header="$temp_root/controller-api-csrf-header"
prompt_ip
if [[ "$command" == install && "$dry_run" == false ]]; then
    initial_system=$(public_system 2>/dev/null || true)
    jq -e '.deviceState == "notSetup" or .deviceState == "setup" or .deviceState == "updateAvailable"' \
        <<<"$initial_system" >/dev/null 2>&1 \
        || die 'UNVR local API is unavailable or returned an unsupported state before destructive reset'
    run_destructive_factory_reset "$initial_system"
fi
if [[ "$command" == install || "$command" == setup-only ]]; then
    initial_system=$(public_system 2>/dev/null || true)
    initial_state=$(jq -r '.deviceState // "unavailable"' <<<"$initial_system" 2>/dev/null || printf unavailable)
    if [[ "$initial_state" == notSetup ]]; then
        if [[ "$dry_run" == true ]]; then
            validate_factory_public_state "$initial_system"
            log 'dry-run: factory UNVR and zero-to-four-drive inventory detected; ownership and SSH were not configured'
            exit 0
        fi
        factory_bootstrap
    elif [[ "$initial_state" == setup || "$initial_state" == updateAvailable ]] && ! nc -z -G 3 "$unvr_ip" 22 >/dev/null 2>&1; then
        if [[ "$dry_run" == true ]]; then
            log 'dry-run: configured stock UNVR detected with SSH disabled; no session or setting was changed'
            exit 0
        fi
        resume_setup_bootstrap
    else
        [[ "$command" != setup-only ]] || die 'setup-only requires a factory or just-configured console with SSH still disabled'
        if [[ "$timeline_active" != true ]]; then
            print_target_summary
        fi
        timeline_step 1 9 'Connect to the existing temporary UNVR owner'
        prompt_ssh_password
    fi
else
    prompt_ssh_password
fi
if [[ "$command" == setup-only ]]; then
    timeline_complete_current
    log 'setup-only complete; firmware and conversion state were not changed'
    exit 0
fi
if [[ "$command" == install ]]; then
    spinner_start 'Establishing secure SSH session'
fi
start_master
if [[ "$command" == install ]]; then
    spinner_stop 'Secure SSH session established'
fi

case "$command" in
    install) run_install ;;
    status) run_status ;;
    disarm) remote_phase disarm-update ;;
    rollback) run_rollback ;;
    unadopt) run_unadopt ;;
esac
