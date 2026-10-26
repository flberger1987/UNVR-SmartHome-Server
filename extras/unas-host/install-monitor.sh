#!/bin/bash
# Health monitor for a converted UNVR, messages via Telegram (run on the Mac).
#
#   extras/unas-host/install-monitor.sh root@<UNAS-IP> [--telegram] [--test]
#
#   --telegram  ask for the bot token (hidden input), then take the chat from
#               the newest message sent to the bot (or a typed chat id); both
#               travel over stdin into /etc/unas-monitor.conf on the UNAS (root
#               only, mode 600) - never into this repository, a command line or
#               the recovery set
#   --test      send a test message with the current state
#
# Installs /usr/local/sbin/unas-monitor and unas-monitor.timer (every 5 min,
# Nice 19). Every run checks, read-only:
#   host: systemctl --failed; the project's units (Docker, netns guard, RAM
#     logs, log trim, backup and boot medium timers, fan set points) active and
#     enabled; the UniFi OS/Drive
#     services (unifi-core, unifi-drive, Postgres, Samba, storage daemons ...);
#     UniFi OS state; NTP sync; RAID (degraded array or failed member - a
#     resync is no alarm); pool mounted and writable, Btrfs error counters;
#     disk use of the pool, the SD card and /run; memory, swap, temperatures (CPU
#     from 85 °C, other sensors from 90 °C), fans;
#     drive temperatures (from the SMART values UniFi's uhwd polls anyway, no
#     extra disk access)
#   containers: every container the stacks deploy (docker compose config;
#     services in inactive profiles are not expected) exists, runs, is not
#     unhealthy, does not restart in a loop and still has its LAN interface
#   inside UniFi OS: unifi-core, Network, Protect, their databases, nginx,
#     failed units; Network status, UniFi OS state, cloud connection, Protect
#   inside LoxBerry: Apache, Mosquitto, cron, every enabled service (plugin
#     daemons), the MQTT gateway process, the web interface, failed units
# A problem is reported once it was seen in 2 runs in a row (no flapping),
# again every 6 h while it lasts, and once more when it is gone ("wieder OK").
# After a boot, a container start (UniFi OS: 60 min, Protect migrations) or a
# unit start, "not running yet" counts as starting, not as a problem.
# No writes to the SD card: state in /run/unas-monitor, output to the journal
# (RAM). On the UNAS: unas-monitor --status | --dry-run | --test.
set -Eeuo pipefail
usage="usage: $0 root@<UNAS-IP> [--telegram] [--test]"
target=${1:?$usage}
shift
telegram=false test=false
while (( $# )); do
    case "$1" in
        --telegram) telegram=true ;;
        --test) test=true ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

remote 'bash -s' <<'EOF'
set -euo pipefail

cat > /usr/local/sbin/unas-monitor <<'SH'
#!/bin/bash
# Health monitor of the UNAS (installed by extras/unas-host/install-monitor.sh).
#   unas-monitor                 check, notify on change (timer, every 5 min)
#   unas-monitor --status        print every check, notify nothing (exit 1 on problems)
#   unas-monitor --dry-run       a timer run that prints the message instead of
#                                sending it (own state in /run/unas-monitor/dry-run)
#   unas-monitor --test          send a test message with the current state
#   unas-monitor --simulate container:<name> | unit:<unit> | unit:<container>/<unit>
#                                also expect this container or unit (repeatable);
#                                for tests: a name that does not exist is missing
#   unas-monitor --set-telegram  read the bot token and the chat id (empty line:
#                                the chat of the bot's newest message) on stdin
# Read-only: never starts, stops or changes a container, unit or disk. State in
# /run/unas-monitor (RAM), output to the journal (RAM): no SD card writes.
# Settings: /etc/unas-monitor.conf (root only, also holds the Telegram token).
set -uo pipefail
umask 077
CONF=/etc/unas-monitor.conf
STATE=/run/unas-monitor

# settings (the conf may override any of them)
NAME=$(hostname)
CONFIRM_RUNS=2          # runs in a row before a problem is reported
REMIND_HOURS=6          # repeat while it lasts
GRACE_MIN=15            # after a boot, a container start or a unit start
GRACE_MIN_UNIFI_OS=60   # UniFi OS: Protect runs its migrations for up to ~45 min
DISK_MAX_PCT=90
MEM_MIN_MB=150
SWAP_MAX_PCT=90
TEMP_MAX_C=90
CPU_TEMP_MAX_C=85       # the CPU sensor (fan set point 75 °C with install-fan-setpoints.sh)
DISK_TEMP_MAX_C=55      # drives (usually rated up to 60 °C)
# host units that must be active and enabled; the backup timer only if enabled
HOST_UNITS="unas-docker unas-netns-guard unas-volatile-logs unas-log-trim var-tmp.mount
  unifi-core unifi-drive unifi-directory ulp-go uos-agent unifi-identity-update
  postgresql@14-main nginx smbd ssh usd ustated usdbd uhwd rclone-rcd earlyoom cron
  systemd-journald systemd-timesyncd"
HOST_UNITS_IF_ENABLED="unas-backup.timer unas-sd-image.timer unas-fan-config ha-mem-guard.timer loxberry-mqtt-guard.timer"
# units inside the containers (LoxBerry: also every enabled service)
UNIFI_OS_UNITS="unifi-core unifi unifi-protect mongodb unifi-mongodb postgresql@14-main
  postgresql@14-protect nginx ulp-go unifi-directory"
LOXBERRY_UNITS="apache2 mosquitto cron loxberry"
LOXBERRY_PROCS="mqttgateway.pl"
IGNORE_FAILED="analytic-report.service"   # failed units that are expected
IGNORE_CONTAINERS=""                       # containers stopped on purpose
TELEGRAM_TOKEN='' TELEGRAM_CHAT_ID=''
[ -r "$CONF" ] && . "$CONF"

mode=run sims=()
while (( $# )); do
    case $1 in
        --status) mode=status ;;
        --dry-run) mode=dry ;;
        --test) mode=test ;;
        --set-telegram) mode=set-telegram ;;
        --simulate) [ -n "${2:-}" ] || { echo '--simulate container:<name> | unit:[<container>/]<unit>' >&2; exit 2; }
                    sims+=("$2"); shift ;;
        -h|--help) sed -n '2,/^set -u/{/^set -u/d;s/^# \{0,1\}//;p}' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# ---- helpers -----------------------------------------------------------------
now=$(date +%s)
read -r up _ < /proc/uptime; up=${up%.*}   # also CLOCK_MONOTONIC (no suspend here)
grace=$(( GRACE_MIN * 60 ))
declare -a PKEYS=() SKEYS=() OKS=() UOK=()
declare -A PROB=() START=() CNT=() NCNT=() U=() CUNITS=() CAUTO=() CPROCS=()
problem()  { [ -n "${PROB[$1]+x}" ] || PKEYS+=("$1"); PROB[$1]=$2; }
starting() { [ -n "${START[$1]+x}" ] || SKEYS+=("$1"); START[$1]=$2; }
pending()  { if (( $3 )); then starting "$1" "$2"; else problem "$1" "$2"; fi; }  # $3: still starting
ok()       { OKS+=("$*"); }
rd()       { local __v=''; { read -r __v < "$2"; } 2>/dev/null; printf -v "$1" '%s' "$__v"; }
addu()     { local __a=$1 __u; shift; for __u; do [[ $__u == *.* ]] || __u+=.service; eval "$__a+=(\"\$__u\")"; done; }
in_list()  { local x=$1 i; shift; for i; do [ "$i" = "$x" ] || [ "$i.service" = "$x" ] && return 0; done; return 1; }
dur() {   # seconds -> "5 min", "2 h 10 min", "3 Tg. 4 h"
    local s=$(( $1 < 0 ? 0 : $1 ))
    if (( s < 3600 )); then printf '%d min' $(( s / 60 ))
    elif (( s < 86400 )); then printf '%d h %d min' $(( s / 3600 )) $(( s % 3600 / 60 ))
    else printf '%d Tg. %d h' $(( s / 86400 )) $(( s % 86400 / 3600 )); fi
}
ulabel() {   # UL = readable name of a unit
    UL=${1%.service}
    case $UL in
        unifi) UL="Network (unifi)" ;;
        unifi-protect) UL="Protect (unifi-protect)" ;;
        unifi-core) UL="UniFi OS (unifi-core)" ;;
        unifi-drive) UL="UniFi Drive (unifi-drive)" ;;
    esac
}
# counters between runs (unit and container restarts, fans seen spinning)
SD=$STATE; [ "$mode" = dry ] && SD=$STATE/dry-run
[ -f "$SD/counters" ] && while read -r k v; do CNT[$k]=$v; done < "$SD/counters"
grew() {   # grew <key> <value>: GREW = growth since the last run (0 on the first)
    local o=${CNT[$1]:-}; NCNT[$1]=$2; GREW=0
    [ -n "$o" ] && (( $2 > o )) && GREW=$(( $2 - o )); return 0
}

# ---- Telegram (token and chat id never on a command line: curl reads its
# config, URL included, from stdin) ---------------------------------------------
cfg_quote() {
    local s=$1
    s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//$'\r'/}
    printf '"%s"' "$s"
}
tg() {   # tg <method> [name=value ...]
    local m=$1 a; shift
    { printf 'url = %s\n' "$(cfg_quote "https://api.telegram.org/bot$TELEGRAM_TOKEN/$m")"
      for a; do printf 'data-urlencode = %s\n' "$(cfg_quote "$a")"; done
    } | curl -s --max-time 10 -K -
}
send() {   # send <text>: Telegram, or only the journal without a conf
    local r
    if [ "$mode" = dry ]; then printf -- '--- würde senden:\n%s\n---\n' "$1"; return 0; fi
    printf '%s\n' "$1" | sed 's/^/| /'
    if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "(Telegram nicht eingerichtet: Nachricht nur im Journal)"; return 0
    fi
    r=$(tg sendMessage "chat_id=$TELEGRAM_CHAT_ID" "text=$1" "disable_web_page_preview=true")
    [[ $r == *'"ok":true'* ]] && return 0
    r=$(jq -r '.description // empty' <<<"$r" 2>/dev/null)
    echo "Telegram: Senden fehlgeschlagen (${r:-keine Antwort}), nächster Versuch beim nächsten Lauf" >&2
    return 1
}

# ---- systemd units -----------------------------------------------------------
read_units() {   # read_units <unit>... < systemctl show output: U[<unit>|<property>]
    local line i=1
    U=()
    while IFS= read -r line; do
        if [ -z "$line" ]; then (( i++ )); continue; fi
        (( i <= $# )) && U[${!i}|${line%%=*}]=${line#*=}
    done
}
PROPS=Type,LoadState,ActiveState,SubState,UnitFileState,ConditionResult,InactiveExitTimestampMonotonic,NRestarts
# unit_check <place> <unit> <place starting 0/1> <grace s> [auto]
#   place: Host or a container; auto: found as enabled (oneshots skipped, their
#   failures show up in the failed list)
unit_check() {
    local p=$1 u=$2 st=$3 g=$4 auto=${5:-} key="unit:$1:$2" lbl since
    local load=${U[$u|LoadState]:-} act=${U[$u|ActiveState]:-} sub=${U[$u|SubState]:-}
    local ie=${U[$u|InactiveExitTimestampMonotonic]:-0} nr=${U[$u|NRestarts]:-0}
    ulabel "$u"; lbl="$p: $UL"
    [ -n "$auto" ] && [ "${U[$u|Type]:-}" = oneshot ] && return 0
    case $load in
        loaded) ;;
        masked) problem "$key" "$lbl ist maskiert"; return ;;
        '') pending "$key" "$lbl: Zustand unbekannt" "$st"; return ;;
        *) pending "$key" "$lbl fehlt (nicht installiert)" "$st"; return ;;
    esac
    since=$(( up - ${ie:-0} / 1000000 ))
    case $act in
        active|reloading) UOK+=("${u%.service}") ;;
        activating)
            if (( st || since < g )); then starting "$key" "$lbl startet (seit $(dur "$since"))"
            elif [ "$sub" = auto-restart ]; then problem "$key" "$lbl startet immer wieder neu"
            else problem "$key" "$lbl hängt im Start (seit $(dur "$since"))"; fi ;;
        failed) pending "$key" "$lbl ist fehlgeschlagen" "$st" ;;
        *) if [ "${U[$u|ConditionResult]:-}" = no ]; then
               pending "$key" "$lbl läuft nicht (Startbedingung nicht erfüllt)" "$st"
           else pending "$key" "$lbl läuft nicht ($act)" "$st"; fi ;;
    esac
    [ "$p" = Host ] && [ "${U[$u|UnitFileState]:-}" = disabled ] &&
        problem "enabled:$p:$u" "$lbl ist nicht aktiviert (startet beim Booten nicht)"
    grew "nrestarts:$p:$u" "${nr:-0}"
    (( GREW )) && problem "restart:$p:$u" "$lbl ist seit der letzten Prüfung ${GREW}× neu gestartet"
    return 0
}
failed_check() {   # failed_check <place> <starting 0/1> <checked unit>... < failed units
    local p=$1 st=$2 f; shift 2
    while read -r f; do
        [ -n "$f" ] || continue
        in_list "$f" $IGNORE_FAILED && continue
        in_list "$f" "$@" && continue   # already reported by unit_check
        ulabel "$f"; pending "failed:$p:$f" "$p: $UL ist fehlgeschlagen" "$st"
    done
}

# ---- host ----------------------------------------------------------------------
check_host() {
    local st=0 u units=() opt=() s ds dec
    (( up < grace )) && st=1
    addu units $HOST_UNITS
    addu opt $HOST_UNITS_IF_ENABLED
    for s in "${sims[@]}"; do [[ $s == unit:* && $s != */* ]] && addu units "${s#unit:}"; done
    read_units "${units[@]}" "${opt[@]}" <<<"$(systemctl show -p "$PROPS" "${units[@]}" "${opt[@]}" 2>/dev/null)"
    UOK=()
    for u in "${units[@]}"; do unit_check Host "$u" "$st" "$grace"; done
    for u in "${opt[@]}"; do [ "${U[$u|UnitFileState]:-}" = enabled ] && unit_check Host "$u" "$st" "$grace"; done
    ok "Host-Dienste aktiv (${#UOK[@]}): ${UOK[*]}"
    failed_check Host "$st" "${units[@]}" "${opt[@]}" \
        <<<"$(systemctl list-units --failed --no-legend --plain 2>/dev/null | awk '{print $1}')"
    # UniFi OS of the host (UNAS identity)
    if [ "${U[unifi-core.service|ActiveState]:-}" = active ]; then
        read -r ds dec <<<"$(curl -sk -m 8 https://127.0.0.1/api/system 2>/dev/null \
            | jq -r '"\(.deviceState) \(.deviceErrorCode)"' 2>/dev/null)"
        if [ -z "$ds" ]; then pending api:Host "Host: UniFi OS (unifi-core) antwortet nicht" "$st"
        elif [ "$ds" = error ] || [ "$dec" != null ]; then problem api:Host "Host: UniFi OS meldet einen Fehler (Status $ds, Code $dec)"
        else ok "Host: UniFi OS Status $ds"; fi
    fi
    s=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    if [ "$s" = no ]; then pending clock "Host: Uhrzeit nicht synchronisiert (NTP)" "$st"
    elif [ "$s" = yes ]; then ok "Uhrzeit per NTP synchronisiert"; fi
}

check_raid() {
    local m d lvl as sa deg mdl bar prog f dev x
    for m in /sys/block/md*/md; do
        [ -d "$m" ] || continue
        d=${m%/md}; d=${d##*/}
        rd lvl "$m/level"; rd as "$m/array_state"; rd sa "$m/sync_action"; rd deg "$m/degraded"
        mdl=$(awk -v d="$d" '$1 == d {p=1; print; next} p && /^[a-z]/ {exit} p' /proc/mdstat)
        bar=$(grep -oE '\[[0-9]+/[0-9]+\] \[[U_]+\]' <<<"$mdl")
        prog=$(sed -nE 's/.*(resync|recovery|reshape|check|repair) *= *([0-9.]+%).*finish=([0-9.]+)min.*/\1 \2, noch ca. \3 min/p;
                       s/.*(resync|recovery)=DELAYED.*/\1 wartet/p' <<<"$mdl" | head -1)
        [[ $prog =~ noch\ ca\.\ ([0-9]+) ]] && prog="${prog% noch*} noch ca. $(dur $(( BASH_REMATCH[1] * 60 )))"
        for f in "$m"/dev-*/state; do
            [ -e "$f" ] || continue
            dev=${f%/state}; dev=${dev##*/dev-}
            rd x "$f"; [[ $x == *faulty* ]] && problem "raid-disk:$d:$dev" "RAID $d: Platte $dev ausgefallen (faulty)"
        done
        case $as in
            clean|active|active-idle|write-pending|read-auto) ;;
            *) problem "raid-state:$d" "RAID $d ($lvl): Zustand $as" ;;
        esac
        if (( ${deg:-0} > 0 )); then
            problem "raid:$d" "RAID $d ($lvl) degradiert: $bar${prog:+, $prog}"
        else ok "RAID $d ($lvl) $bar${prog:+, $prog (kein Alarm)}"; fi
    done
}

V='' A=''
check_storage() {
    local st=0 opts errs pct mnt lbl use=() avail swp t ty z h f n v k lab pmin lim temps=() fans=()
    (( up < grace )) && st=1
    for v in /volume/*-*-*-*-*; do mountpoint -q "$v" && { V=$v; break; }; done
    if [ -z "$V" ]; then pending pool "Speicherpool nicht eingehängt" "$st"
    else
        A=$V/.unas-apps
        opts=$(findmnt -no OPTIONS "$V")
        [[ ,$opts, == *,ro,* ]] && problem pool-ro "Speicherpool nur lesbar (read-only) - Dateisystemfehler?"
        errs=$(btrfs device stats "$V" 2>/dev/null | awk 'NF == 2 && $2 + 0 != 0 {sub(/.*\]\./, "", $1); printf "%s%s=%s", s, $1, $2; s=", "}')
        if [ -n "$errs" ]; then problem btrfs "Btrfs meldet Fehler auf dem Speicherpool: $errs"
        else ok "Speicherpool eingehängt (${opts%%,*}), Btrfs-Fehlerzähler 0"; fi
    fi
    while read -r _ _ _ _ pct mnt; do
        [ -n "$mnt" ] || continue
        pct=${pct%\%}
        case $mnt in "$V") lbl=Speicherpool ;; /) lbl="System (SD-Karte)" ;; /data) lbl="/data (SD-Karte)" ;; *) lbl=$mnt ;; esac
        if (( pct >= DISK_MAX_PCT )); then problem "disk:$mnt" "Speicher fast voll: $lbl zu $pct % belegt"
        else use+=("$lbl $pct %"); fi
    done <<<"$(df -P ${V:+"$V"} / /data /run 2>/dev/null | tail -n +2)"
    (( ${#use[@]} )) && ok "Belegung: $(IFS=,; echo "${use[*]}" | sed 's/,/, /g')"
    read -r avail swp < <(awk '/^MemAvailable:/ {a=$2} /^SwapTotal:/ {t=$2} /^SwapFree:/ {f=$2}
        END {print int(a/1024), (t > 0 ? int((t-f)*100/t) : 0)}' /proc/meminfo)
    (( avail < MEM_MIN_MB )) && problem mem "Arbeitsspeicher knapp: nur $avail MB verfügbar"
    (( swp >= SWAP_MAX_PCT )) && problem swap "Swap zu $swp % belegt"
    ok "Arbeitsspeicher verfügbar $avail MB, Swap $swp % belegt"
    for z in /sys/class/thermal/thermal_zone*; do
        rd t "$z/temp"; rd ty "$z/type"; [ -n "$t" ] || continue
        ty=${ty%-thermal}; ty=${ty^^}; t=$(( t / 1000 )); temps+=("$ty $t °C")
        lim=$TEMP_MAX_C; [ "$ty" = CPU ] && lim=$CPU_TEMP_MAX_C
        (( t >= lim )) && problem "temp:$ty" "Temperatur hoch: $ty $t °C (Grenze $lim °C)"
    done
    for h in /sys/class/hwmon/hwmon*; do
        for f in "$h"/temp*_input; do
            [ -e "$f" ] || continue
            n=${f%_input}; rd v "${n}_fault"; [ "$v" = 1 ] && continue
            rd t "$f"; rd lab "${n}_label"; lab=${lab:-${n##*/}}; t=$(( t / 1000 )); temps+=("$lab $t °C")
            rd v "${n}_alarm"
            if (( t >= TEMP_MAX_C )) || [ "$v" = 1 ]; then problem "temp:${h##*/}:${n##*/}" "Temperatur hoch: $lab $t °C"; fi
        done
        # a fan seen spinning that stops while the fans are driven (every pwm > 0)
        pmin=$(cat "$h"/pwm[0-9] 2>/dev/null | sort -n | head -1)
        for f in "$h"/fan*_input; do
            [ -e "$f" ] || continue
            rd v "$f"; n=${f##*/}; n=${n%_input}; k="fan:${h##*/}:$n"
            if (( v > 0 )); then NCNT[$k]=1; fans+=("$v")
            elif [ -n "${CNT[$k]:-}" ]; then
                NCNT[$k]=1
                (( ${pmin:-0} > 0 )) && problem "$k" "Lüfter ${n#fan} steht (0 U/min)"
            fi
        done
    done
    ok "Temperaturen: $(IFS=,; echo "${temps[*]}" | sed 's/,/, /g')${fans[*]:+; Lüfter ${fans[*]} U/min}"
    check_disk_temps
}

# drive temperatures: UniFi's uhwd polls SMART anyway and keeps the values in
# a cache; reading that adds no disk access (no smartctl here)
check_disk_temps() {
    local c=/run/ustd/hw_polling.cache n t age dt=()
    if [ ! -r "$c" ]; then pending disktemp "Plattentemperaturen nicht verfügbar ($c fehlt)" 0; return; fi
    age=$(( $(date +%s) - $(stat -c %Y "$c") ))
    (( age > 1800 )) && problem disktemp-stale "Plattentemperaturen seit $(( age / 60 )) min nicht aktualisiert (uhwd?)"
    while read -r n t; do
        [[ $t =~ ^[0-9]+$ ]] || continue
        dt+=("$n $t °C")
        (( t >= DISK_TEMP_MAX_C )) && problem "disktemp:$n" "Festplatte zu warm: $n $t °C (Grenze $DISK_TEMP_MAX_C °C)"
    done < <(jq -r '.disk_sysfs // {} | to_entries[] | "\(.value.node) \(.value.smart.temperature // "")"' "$c" 2>/dev/null | sort)
    if (( ${#dt[@]} )); then ok "Plattentemperaturen: $(IFS=,; echo "${dt[*]}" | sed 's/,/, /g')"
    else pending disktemp "Plattentemperaturen: keine Werte in $c" 0; fi
}

# ---- containers ------------------------------------------------------------------
CUNITS[unifi-os]=$UNIFI_OS_UNITS
CUNITS[loxberry]=$LOXBERRY_UNITS CAUTO[loxberry]=1 CPROCS[loxberry]=$LOXBERRY_PROCS
for s in "${sims[@]}"; do [[ $s == unit:*/* ]] && { s=${s#unit:}; CUNITS[${s%%/*}]+=" ${s#*/}"; }; done

expected_containers() {   # containers the stacks deploy; cached until a compose file changes
    local cache=$STATE/containers sig s f out all=''
    local files=("$A"/data/stacks/*/compose.y*ml "$A"/data/stacks/*/docker-compose.y*ml "$A"/data/stacks/*/.env
                 "$A"/dockge/compose.y*ml "$A"/dockge/.env)
    sig=$(stat -c '%n %Y %s' "${files[@]}" 2>/dev/null | md5sum)
    if [ -f "$cache" ] && [ "$(head -1 "$cache")" = "$sig" ]; then tail -n +2 "$cache"; return; fi
    for s in "$A"/data/stacks/*/ "$A"/dockge/; do
        f=$(ls "$s"compose.yaml "$s"compose.yml "$s"docker-compose.yaml "$s"docker-compose.yml 2>/dev/null | head -1)
        [ -n "$f" ] || continue
        if out=$(cd "$s" && timeout 60 docker compose -f "$f" config --format json 2>/dev/null) &&
           out=$(jq -r '.name as $p | .services | to_entries[] | .value.container_name // "\($p)-\(.key)-1"' <<<"$out"); then
            all+="$out"$'\n'
        else
            echo "!${s%/}"; sig=''   # not cached: try again next run
        fi
    done
    all=$(sort -u <<<"$all" | sed '/^$/d')
    if [ -n "$sig" ]; then mkdir -p "$STATE"; printf '%s\n%s\n' "$sig" "$all" > "$cache.new" && mv "$cache.new" "$cache"; fi
    printf '%s\n' "$all"
}

# script run by sh inside a container (docker exec -i ... sh -s); prints sections
read -r -d '' INNER <<'IN'
extra=''
if [ "$AUTO" = 1 ]; then
    for u in $(systemctl list-unit-files --type=service --state=enabled --no-legend 2>/dev/null | awk '$1 !~ /@\./ {print $1}'); do
        case " $UNITS " in *" $u "*) ;; *) extra="$extra $u" ;; esac
    done
fi
echo @auto; for u in $extra; do echo "$u"; done
echo @show; systemctl show -p "$PROPS" $UNITS $extra
echo @failed; systemctl list-units --failed --no-legend --plain 2>/dev/null | awk '{print $1}'
echo @procs; for p in $PROCS; do if pgrep -f "$p" >/dev/null 2>&1; then echo "$p 1"; else echo "$p 0"; fi; done
case $WHAT in
unifi-os)
    echo @network; curl -s -m 8 http://127.0.0.1:8080/status; echo
    echo @system; curl -sk -m 8 https://127.0.0.1/api/system; echo
    echo @protect; curl -s -m 8 http://127.0.0.1:7080/api/ucore/status; echo ;;   # what unifi-core polls
loxberry)
    echo @web; curl -s -m 8 -o /dev/null -w '%{http_code}' http://127.0.0.1/; echo ;;
esac
echo @end
IN

inner() {   # inner <container> <starting 0/1> <grace s>: checks inside a systemd container
    local c=$1 cst=$2 g=$3 u ul=() extra=() out line cur rc run db ds dec cc ra code p r
    local -A sec=()
    addu ul ${CUNITS[$c]}
    out=$( { printf "UNITS='%s' AUTO='%s' PROCS='%s' WHAT='%s' PROPS='%s'\n" "${ul[*]}" "${CAUTO[$c]:-}" "${CPROCS[$c]:-}" "$c" "$PROPS"
             printf '%s\n' "$INNER"; } | timeout 60 docker exec -i "$c" sh -s 2>/dev/null)
    if [[ $out != *@end* ]]; then pending "exec:$c" "$c: Prüfung im Container fehlgeschlagen (docker exec)" "$cst"; return; fi
    while IFS= read -r line; do
        case $line in @*) cur=${line#@}; sec[$cur]=''; continue ;; esac
        sec[$cur]+="$line"$'\n'
    done <<<"$out"
    extra=(${sec[auto]:-})
    read_units "${ul[@]}" "${extra[@]}" <<<"${sec[show]:-}"
    UOK=()
    for u in "${ul[@]}"; do unit_check "$c" "$u" "$cst" "$g"; done
    for u in "${extra[@]}"; do unit_check "$c" "$u" "$cst" "$g" auto; done
    failed_check "$c" "$cst" "${ul[@]}" "${extra[@]}" <<<"${sec[failed]:-}"
    while read -r p r; do
        [ -n "$p" ] || continue
        if [ "$r" = 1 ]; then UOK+=("$p"); else pending "proc:$c:$p" "$c: Prozess $p läuft nicht" "$cst"; fi
    done <<<"${sec[procs]:-}"
    case $c in
    unifi-os)
        if [ "${U[unifi.service|ActiveState]:-}" = active ]; then
            read -r rc run db <<<"$(jq -r '.meta | "\(.rc) \(.server_running) \(.db_connected)"' <<<"${sec[network]:-}" 2>/dev/null)"
            if [ -z "$rc" ]; then pending "app:$c:network" "$c: Network antwortet nicht" "$cst"
            elif [ "$run $db" != "true true" ]; then pending "app:$c:network" "$c: Network meldet eine Störung (Server läuft: $run, Datenbank verbunden: $db)" "$cst"
            else UOK+=(Network-Status); fi
        fi
        if [ "${U[unifi-core.service|ActiveState]:-}" = active ]; then
            read -r ds dec cc ra <<<"$(jq -r '"\(.deviceState) \(.deviceErrorCode) \(.cloudConnected) \(.remoteAccessEnabled)"' <<<"${sec[system]:-}" 2>/dev/null)"
            if [ -z "$ds" ]; then pending "app:$c:core" "$c: UniFi OS (unifi-core) antwortet nicht" "$cst"
            elif [ "$ds" = error ] || [ "$dec" != null ]; then problem "app:$c:core" "$c: UniFi OS meldet einen Fehler (Status $ds, Code $dec)"
            else UOK+=("UniFi-OS-Status:$ds"); fi
            if [ "$ra" = true ] && [ "$cc" = false ]; then pending "cloud:$c" "$c: keine Verbindung zur UniFi-Cloud (Remote Access)" "$cst"
            elif [ "$cc" = true ]; then UOK+=(Cloud); fi
        fi
        if [ "${U[unifi-protect.service|ActiveState]:-}" = active ]; then
            ds=$(jq -r '.controllerStatus // empty' <<<"${sec[protect]:-}" 2>/dev/null)
            case $ds in
                READY) UOK+=(Protect-Status:READY) ;;
                '') pending "app:$c:protect" "$c: Protect antwortet nicht" "$cst" ;;
                *) pending "app:$c:protect" "$c: Protect meldet Status $ds" "$cst" ;;
            esac
        fi ;;
    loxberry)
        if [ "${U[apache2.service|ActiveState]:-}" = active ]; then
            code=${sec[web]:-}; code=${code//$'\n'/}
            case $code in
                2??|3??|401) UOK+=(Web) ;;
                *) pending "app:$c:web" "$c: Weboberfläche antwortet nicht (HTTP ${code:-000})" "$cst" ;;
            esac
        fi ;;
    esac
    ok "$c: aktiv (${#UOK[@]}): ${UOK[*]}"
}

check_containers() {
    local st=0 c names=() out rc line ec status started pid health rcount ecode netmode cup g cst s
    local -A REC=() MISS=()
    (( up < grace )) && st=1
    [ -n "$A" ] && [ -d "$A" ] || return 0
    while read -r line; do
        case $line in '') ;; !*) problem "stack:${line#!}" "Stack ${line##*/}: compose-Datei nicht lesbar (docker compose config)" ;;
                      *) in_list "$line" $IGNORE_CONTAINERS || names+=("$line") ;; esac
    done <<<"$(expected_containers)"
    for s in "${sims[@]}"; do [[ $s == container:* ]] && names+=("${s#container:}"); done
    (( ${#names[@]} )) || return 0
    out=$(timeout 60 docker inspect -f '{{.Name}}|{{.State.Status}}|{{.State.StartedAt}}|{{.State.Pid}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}|{{.RestartCount}}|{{.State.ExitCode}}|{{.HostConfig.NetworkMode}}' "${names[@]}" 2>&1)
    rc=$?
    while IFS= read -r line; do
        case $line in
            /*) REC[${line%%|*}]=$line ;;
            *"No such object: "*) MISS[${line##*: }]=1 ;;
            ?*) ec=$line ;;
        esac
    done <<<"$out"
    if (( rc != 0 )) && (( ${#REC[@]} + ${#MISS[@]} == 0 )); then
        pending docker "Docker reagiert nicht${ec:+ ($ec)}" "$st"; return
    fi
    for c in "${names[@]}"; do
        if [ -z "${REC[/$c]:-}" ]; then pending "ctr:$c" "Container $c fehlt" "$st"; continue; fi
        IFS='|' read -r _ status started pid health rcount ecode netmode <<<"${REC[/$c]}"
        grew "restarts:$c" "${rcount:-0}"
        (( GREW )) && problem "crestart:$c" "Container $c ist seit der letzten Prüfung ${GREW}× neu gestartet"
        case $status in
            running) ;;
            restarting) problem "ctr:$c" "Container $c startet immer wieder neu (Exit-Code $ecode)"; continue ;;
            *) pending "ctr:$c" "Container $c läuft nicht ($status, Exit-Code $ecode)" "$st"; continue ;;
        esac
        cup=$(( now - $(date -d "$started" +%s 2>/dev/null || echo "$now") ))
        g=$grace; [ "$c" = unifi-os ] && g=$(( GRACE_MIN_UNIFI_OS * 60 ))
        cst=0; (( cup < g )) && cst=1
        [ "$health" = unhealthy ] && problem "health:$c" "Container $c meldet „unhealthy“ (Healthcheck)"
        if [ "$netmode" != none ] && [ "$netmode" != host ] &&
           ! awk -F: 'NR > 2 && $1 !~ /^ *lo$/ {f=1} END {exit !f}' "/proc/$pid/net/dev" 2>/dev/null; then
            problem "net:$c" "Container $c hat keine Netzwerkschnittstelle mehr (nur lo)"
        fi
        ok "Container $c läuft seit $(dur "$cup")${health:+ ($health)}$( (( cst )) && echo ', Startphase')"
        [ -n "${CUNITS[$c]+x}" ] && inner "$c" "$cst" "$g"
    done
}

run_checks() { check_host; check_raid; check_storage; check_containers; }

# ---- messages ------------------------------------------------------------------
stamp() { date '+%d.%m.%Y %H:%M'; }
notify() {   # compare with the last runs, send what changed, save the state
    local sf=$SD/state k c f s m nn no nc remind=0 head text L=()
    local -A Sc=() Sf=() Ss=() Sm=() Nc=() Nf=() Ns=() Nm=()
    local -a order=() new=() open=() cleared=()
    if [ -f "$sf" ]; then
        while IFS=$'\t' read -r k c f s m; do
            [ -n "$k" ] || continue
            Sc[$k]=$c Sf[$k]=$f Ss[$k]=$s Sm[$k]=$m; order+=("$k")
        done < "$sf"
    elif [ "$mode" = run ] && (( up < 1800 )); then
        send "ℹ️ $NAME wurde neu gestartet (vor $(dur "$up")). Die Überwachung läuft."$'\n\n'"$(stamp)"
    fi
    for k in "${PKEYS[@]}"; do
        c=$(( ${Sc[$k]:-0} + 1 )) f=${Sf[$k]:-$now} s=${Ss[$k]:-0}
        Nc[$k]=$c Nf[$k]=$f Ns[$k]=$s Nm[$k]=${PROB[$k]}
        if (( s > 0 )); then open+=("$k"); (( now - s >= REMIND_HOURS * 3600 )) && remind=1
        elif (( c >= CONFIRM_RUNS )); then new+=("$k"); fi
    done
    for k in "${order[@]}"; do
        [ -n "${PROB[$k]+x}" ] && continue
        if [ -n "${START[$k]+x}" ] && (( ${Ss[$k]:-0} > 0 )); then
            # reported and now starting again: still open until it is up
            Nc[$k]=${Sc[$k]} Nf[$k]=${Sf[$k]} Ns[$k]=${Ss[$k]} Nm[$k]=${START[$k]}; open+=("$k")
        elif (( ${Ss[$k]:-0} > 0 )); then cleared+=("$k"); fi
    done
    nn=${#new[@]} no=${#open[@]} nc=${#cleared[@]}
    if (( nn + nc + remind )); then
        if (( nn )); then head="🔴 $NAME: $( (( nn == 1 )) && echo Problem || echo "$nn Probleme")"
        elif (( remind )); then head="⏰ $NAME: $( (( no == 1 )) && echo 'Problem besteht weiter' || echo "$no Probleme bestehen weiter")"
        elif (( no )); then head="🟡 $NAME: teilweise wieder OK"
        else head="✅ $NAME: wieder alles OK"; fi
        L=("$head")
        for k in "${new[@]}"; do L+=("• ${Nm[$k]}"); done
        if (( nc )); then
            (( nn || no )) && L+=("" "Wieder OK:")
            for k in "${cleared[@]}"; do L+=("• ${Sm[$k]} - behoben nach $(dur $(( now - ${Sf[$k]} )))"); done
        fi
        if (( no )); then
            (( nn || nc )) && L+=("" "Weiterhin offen:")
            for k in "${open[@]}"; do L+=("• ${Nm[$k]} - seit $(dur $(( now - ${Nf[$k]} )))"); done
        fi
        (( ${#L[@]} > 40 )) && L=("${L[@]:0:39}" "… und $(( ${#L[@]} - 39 )) weitere Zeilen")
        text=$(printf '%s\n' "${L[@]}")$'\n\n'"$(stamp)"
        if send "$text"; then
            for k in "${new[@]}"; do Ns[$k]=$now; done
            if (( nn || remind )); then for k in "${open[@]}"; do Ns[$k]=$now; done; fi
        else   # keep the cleared ones (count 0) to send "wieder OK" next time
            for k in "${cleared[@]}"; do Nc[$k]=0 Nf[$k]=${Sf[$k]} Ns[$k]=${Ss[$k]} Nm[$k]=${Sm[$k]}; done
        fi
    fi
    mkdir -p "$SD"
    { for k in "${!Nc[@]}"; do printf '%s\t%s\t%s\t%s\t%s\n' "$k" "${Nc[$k]}" "${Nf[$k]}" "${Ns[$k]}" "${Nm[$k]}"; done; } > "$sf.new" && mv "$sf.new" "$sf"
    { for k in "${!NCNT[@]}"; do printf '%s %s\n' "$k" "${NCNT[$k]}"; done; } > "$SD/counters.new" && mv "$SD/counters.new" "$SD/counters"
}

# ---- set up Telegram (token and chat id on stdin) ------------------------------
set_telegram() {
    local token='' chat='' r bot info ctype cname
    IFS= read -r token || true; IFS= read -r chat || true
    token=${token//[[:space:]]/} chat=${chat//[[:space:]]/}
    [[ $token =~ ^[0-9]{5,}:[A-Za-z0-9_-]{30,}$ ]] || { echo "Das ist kein Bot-Token (Form 123456789:AA..., von @BotFather)." >&2; return 2; }
    TELEGRAM_TOKEN=$token
    r=$(tg getMe)
    [[ $r == *'"ok":true'* ]] || { echo "Telegram lehnt den Token ab: $(jq -r '.description // "keine Antwort"' <<<"$r" 2>/dev/null || echo 'keine Antwort')" >&2; return 1; }
    bot=$(jq -r '.result.username' <<<"$r")
    if [ -z "$chat" ]; then
        r=$(tg getUpdates)
        [[ $r == *'"ok":true'* ]] || { echo "getUpdates fehlgeschlagen: $(jq -r '.description // "keine Antwort"' <<<"$r" 2>/dev/null || echo 'keine Antwort')" >&2; return 1; }
        info=$(jq -r '[.result[] | (.message // .edited_message // .channel_post // .my_chat_member // empty) | .chat] | last // empty
            | "\(.id)\t\(.type)\t\(.title // ([.first_name, .last_name] | map(select(. != null)) | join(" ")))"' <<<"$r")
        if [ -z "$info" ]; then
            echo "Keine Nachricht an @$bot gefunden: in Telegram @$bot öffnen, Start tippen oder etwas schreiben, dann noch einmal." >&2
            return 1
        fi
        IFS=$'\t' read -r chat ctype cname <<<"$info"
        echo "Chat gefunden: $cname ($ctype)"
    fi
    [[ $chat =~ ^-?[0-9]+$ ]] || { echo "Die Chat-ID ist eine Zahl." >&2; return 2; }
    # the bot's own id (the number before ":" in the token) is not a chat
    [ "$chat" != "${token%%:*}" ] || { echo "Das ist die ID des Bots, nicht deine. Enter ohne Eingabe übernimmt den Chat, in dem du @$bot geschrieben hast." >&2; return 2; }
    # only keep a chat the bot may write to (sendChatAction shows nothing in the chat)
    r=$(tg sendChatAction "chat_id=$chat" "action=typing")
    [[ $r == *'"ok":true'* ]] || { echo "@$bot kann an Chat $chat nicht schreiben: $(jq -r '.description // "keine Antwort"' <<<"$r" 2>/dev/null || echo 'keine Antwort'). Nichts gespeichert." >&2; return 1; }
    { if [ -f "$CONF" ]; then grep -v -E '^(TELEGRAM_TOKEN|TELEGRAM_CHAT_ID)=' "$CONF" || true
      else
        echo "# unas-monitor settings (root only: holds the Telegram bot token)."
        echo "# Overrides, all settings: head -60 /usr/local/sbin/unas-monitor"
        echo "#IGNORE_CONTAINERS=\"name\"        # containers stopped on purpose"
        echo "#IGNORE_FAILED=\"analytic-report.service other.service\""
        echo "#GRACE_MIN=15 GRACE_MIN_UNIFI_OS=60 DISK_MAX_PCT=90 TEMP_MAX_C=90 CPU_TEMP_MAX_C=85 DISK_TEMP_MAX_C=55"
      fi
      printf "TELEGRAM_TOKEN='%s'\nTELEGRAM_CHAT_ID='%s'\n" "$token" "$chat"
    } > "$CONF.new" && chown root:root "$CONF.new" && chmod 600 "$CONF.new" && mv "$CONF.new" "$CONF"
    echo "Telegram eingerichtet: Bot @$bot, gespeichert in $CONF (nur root)"
}

# ---- main ------------------------------------------------------------------------
case $mode in
set-telegram) set_telegram; exit ;;
status)
    run_checks
    echo "$NAME, $(stamp), Host läuft seit $(dur "$up")"
    for m in "${OKS[@]}"; do printf 'OK       %s\n' "$m"; done
    for k in "${SKEYS[@]}"; do printf 'STARTET  %s\n' "${START[$k]}"; done
    for k in "${PKEYS[@]}"; do printf 'PROBLEM  %s\n' "${PROB[$k]}"; done
    if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then echo "Telegram: eingerichtet ($CONF)"
    else echo "Telegram: nicht eingerichtet (nur Journal)"; fi
    if [ -s "$STATE/state" ]; then
        echo "Zuletzt gemeldet und offen:"
        awk -F'\t' '$4 > 0 {print "  " $5}' "$STATE/state"
    fi
    echo "Ergebnis: ${#PKEYS[@]} Problem(e), ${#SKEYS[@]} im Start"
    (( ${#PKEYS[@]} == 0 )); exit ;;
test)
    if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "Telegram nicht eingerichtet: install-monitor.sh ... --telegram" >&2; exit 1
    fi
    run_checks
    L=("🧪 $NAME: Test der Überwachung, Telegram funktioniert.")
    if (( ${#PKEYS[@]} )); then L+=("Aktuell ${#PKEYS[@]} Problem(e):"); for k in "${PKEYS[@]}"; do L+=("• ${PROB[$k]}"); done
    else L+=("Aktuell: alles OK."); fi
    for k in "${SKEYS[@]}"; do L+=("• ${START[$k]}"); done
    if send "$(printf '%s\n' "${L[@]}")"$'\n\n'"$(stamp)"; then echo "Testnachricht gesendet."; else exit 1; fi
    exit ;;
esac

# timer run or --dry-run: one at a time
mkdir -p "$SD"
exec 9>"$SD/lock"; flock -n 9 || { echo "unas-monitor läuft bereits"; exit 0; }
run_checks
notify
if (( ${#PKEYS[@]} )); then
    printf '%s Problem(e): %s\n' "${#PKEYS[@]}" "$(for k in "${PKEYS[@]}"; do printf '%s; ' "${PROB[$k]}"; done)"
else echo "alles OK${SKEYS[*]:+ (${#SKEYS[@]} im Start)}"; fi
exit 0
SH
chmod 755 /usr/local/sbin/unas-monitor

cat > /etc/systemd/system/unas-monitor.service <<'UNIT'
[Unit]
Description=UNAS health monitor (Telegram on change)
After=unas-docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/unas-monitor
Nice=19
IOSchedulingClass=best-effort
IOSchedulingPriority=7
TimeoutStartSec=4min
UNIT
cat > /etc/systemd/system/unas-monitor.timer <<'UNIT'
[Unit]
Description=UNAS health monitor every 5 minutes

[Timer]
OnCalendar=*:0/5
AccuracySec=30s
Persistent=false

[Install]
WantedBy=timers.target
UNIT
[ -f /etc/unas-monitor.conf ] && chmod 600 /etc/unas-monitor.conf
systemctl daemon-reload
systemctl enable --now unas-monitor.timer >/dev/null 2>&1
echo "installed: unas-monitor, every 5 min (next run: $(systemctl show -p NextElapseUSecRealtime --value unas-monitor.timer))"
if [ -f /etc/unas-monitor.conf ] && grep -q '^TELEGRAM_TOKEN=.' /etc/unas-monitor.conf; then
    echo "Telegram: set up (/etc/unas-monitor.conf)"
else
    echo "Telegram: not set up yet (messages only in the journal): run with --telegram"
fi
EOF

if [[ "$telegram" == true ]]; then
    echo 'Telegram-Bot: in Telegram @BotFather öffnen, /newbot, Namen und Benutzernamen wählen;'
    echo 'BotFather antwortet mit dem Token (123456789:AA...).'
    read -r -s -p 'Bot-Token einfügen (Eingabe unsichtbar): ' token; echo
    [[ "$token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]] || { echo 'Das ist kein Bot-Token.' >&2; exit 2; }
    echo 'Jetzt in Telegram den neuen Bot öffnen und ihm eine Nachricht schicken (z. B. Start).'
    read -r -s -p 'Danach Enter drücken (oder eine Chat-ID eingeben, unsichtbar): ' chat; echo
    # over stdin only: no secret on a command line, in a file on the Mac or in the shell history
    printf '%s\n%s\n' "$token" "$chat" | remote 'unas-monitor --set-telegram'
    unset token chat
fi
if [[ "$test" == true ]]; then
    remote 'unas-monitor --test'
fi
