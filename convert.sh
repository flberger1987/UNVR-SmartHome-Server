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

readonly REMOTE_ENGINE_SHA256=25673c5b3da81c7d838885e8bd8fa85ece5458bbae7392971a8003ac321373fe
readonly UPDATE_PROFILE_BUILDER_SHA256=0bdcb6ae963239551f963080998f2864acb733c110a647db9bace7ec6e8bb6d1
readonly DEBIAN_DRIVE_CLOSURE_SHA256=52e38d9730228dc2e6632cccbcd777498450d2b79f0ebf1077fa34dec8d197f9
readonly DEBIAN_KBUILD_CLOSURE_SHA256=fb99e5bfe01f99d9f40f613e7610ec34c77a1c67c0264f74b26cc455487471f8
readonly PAYLOAD_CONTRACT_SHA256=483b83cd8e3e72c07ecbe5d81c2472cb50daa890da9f341e55f096835f765ce8
readonly UBIQUITI_DRIVE_PACKAGES_SHA256=8fdfe83b30b934cc5b00b21a9a9ec812901ac979ffd65b9985b0fd012bf31067
readonly CORE_IDENTITY_BUILDER_SHA256=806eab270b38060622a754bb0ffcf1fcb648d6b85bbfaf94cd1498ce5ab931ae
readonly CORE_5X_BUILDER_SHA256=472ab10f713242d2218069b1717b2c45ee75abce434b6ac6db51c649293895d4
readonly IDENTITY_OVERLAY_BUILDER_SHA256=c00fb9a5073d6f4c9c4a67903766cd97d0a789e628da49853eca7c191c89a84f
readonly PORTAL_BUILDER_SHA256=8554cbb7f31afd281466930a492c51a33ae1820d9b981aabb3adcaa0abb8625a
readonly STORAGE_UI_VERIFIER_SHA256=20014943e53248798094a8db40f9c84f6825db3100f4d2c561448f4890524427
readonly WSDD5_BUILDER_SHA256=215243a2b8dff1073b7810a8047e7ea24efbf37d6be2414bc334d826f2e15d2a
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
readonly EMBEDDED_HELPERS_SHA256=9bd6415694381b5cdbdcc8460422a02121aabf5f5c6c143d04e6e9229cf2dc84
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
                if escape_sequence:
                    if 64 <= byte <= 126:
                        escape_sequence = False
                    continue
                if byte == 27:
                    escape_sequence = True
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
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
a6FLqtp+2gDdPBwN0DPjg9pv748G53BsyLuLXa6LsZ50vaQpxj6tCqrBky+GRBAmjr5V630QzDtk
g0hMveGgKM6PjYGaSyLC6PMRI6FKhRXI+HgBGZACaZQghwwzMTH7mPHkVIIGCSaVWGR68SapI74P
Oyjj7VN8LLXM29dTVN0+6FuVbjFfun+6K/Hxmx0r6vXRM6fxm+4LbuLTXX5XH/efu4J487f9IqSf
MM/WNZ999DbwYetUvf/ovePqbWBQiQ/Lj372QVDFM1/wovP+5tsW39zlVx2rdzi2A09j+ab7gh4j
7GNM/B8zsvhwkf1rfMfz8b9QsMJu439HNRMSAl7/Z/zvH+Pfbvzvn8x+ef0Ba2Flb/QwOWyDtWC5
mP26x8JiV8x3g13X96Yrg3N1DHHRH7faLTBwnm6xq1DKv26+jt8s8KD2tKjlp7Ds6W7FU5+v39U7
ehfRFH68nQJ5GSUK4/zTQnc/PXL3OCr3cGucicq1V/JK6zcfaQ5vHzAZmFed4uXN5W3X/OvWTV84
h8zN77efgJy86mN9xRbeXD3c31znb94wnBqobcn/LqAX20W5lKJX7PVeesDVdCDyJqhSfCwk7xaB
rIwimwIriQkOFbPzMT+aszKQrSx5AfiVFIxBfATA1vpXuz2q5U2LN4u6G5b8ckjyz2bfv3p1x1vw
Gx5HXbWyvDoIa374Zvnu/k73+9Tr2z7/UKI/m3F+3+DVxWKJpXSRnoBQHi/Y9R9/8bN+sIKarIQh
Qvt+nF4/VsaVv8ECvX39xewnJwvz/U1BIUx5+bPZ6un3T8v143us+o/7B1fx7gfP/ens4FFffL6D
Kf58Rt+Qy7VSuUR3X3Co2YnZ/qHx2n/Bi/FNpHYf8WknvhCsvf66/7YCHlzw0KzziR9givtf7+kv
Ny3iF/7pdJbco71Hwy48vH+71pu9KwVvzP/pqQK9zP+f2by9+fyz3/+Pqfz7z6fFcuKMZdX2fnZ0
hV+xx5tPp3xydYynNl68vWV4R7/e+xxHoR9XH1xwTLJAblz66N53E1O9efPZ/j3kdB63dc3bPZ/b
fGn/5DNuuHu9mJ1yNt96S73ePO/A2fVUr67u7+rVfTvTuVWH1CrIfi+afopSV3/4vq4D+g/7OB1o
/2vF8O817njg1r4/fzxHr2ecvNat/QFuXh8VCbd+/kteSC9GEn+yG9aeE8vZbn6kS1ZmEMDOFcns
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
wZ+fPz9/fv6DP/8P2Mp5mwA4BgA=
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
    if [[ -z "$ui_account_password" ]]; then
        prompt_secret 'UI Account password: ' ui_account_password
        [[ -n "$ui_account_password" ]] || die 'UI Account password cannot be empty'
    fi
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
                    require_api_success "$status" "$authenticator_type MFA code request"
                    spinner_stop "$authenticator_type verification code sent"
                    ;;
                TOTP|BACKUP_CODE) ;;
                *) die "unsupported MFA authenticator type: $authenticator_type" ;;
            esac
            if [[ "$sso_authenticated" != true ]]; then
                prompt_secret 'UI Account MFA verification code: ' mfa_token
                [[ -n "$mfa_token" ]] || die 'MFA verification code cannot be empty'
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

prepare_update_profiles() {
    local output_dir="$temp_root/update-profiles" output bundle expected_bundle expected_hash actual_hash args=()
    [[ -z "$unvr5_firmware" ]] || args+=(--unvr-5 "$unvr5_firmware")
    [[ -z "$unas5_firmware" ]] || args+=(--unas-5 "$unas5_firmware")
    if [[ -n "$unvr5_firmware" || -n "$unas5_firmware" ]]; then
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
    local system_json=$1 reset_output reset_rc
    confirm_destructive_reset
    ensure_reset_ssh_access "$system_json"
    capture_remote_phase 'Validated the physical UNVR and destructive reset boundary' factory-reset-preflight
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
