#!/bin/bash
# Memory guard for the Home Assistant container on the UNAS (run on the Mac).
#
#   extras/unas-apps/homeassistant/install-mem-guard.sh root@<UNAS-IP> [--limit 1200] [--warn 900] [--no-mqtt]
#   extras/unas-apps/homeassistant/install-mem-guard.sh root@<UNAS-IP> --remove
#
# The UNAS kernel has no cgroups, so Docker cannot limit a container's memory.
# A Home Assistant that grows (a leaking custom integration, a map renderer)
# first fills the swap and then starves UniFi OS, Protect and their databases
# (seen 2026-10-25: MongoDB shut down uncleanly, Protect restarted).
#
# Installs /usr/local/sbin/ha-mem-guard and ha-mem-guard.timer (every 2 min,
# Nice 19). Each run adds up RAM and swap of the Home Assistant process:
#   - above --warn (MB): one Telegram message, another one when it is back below
#   - above --limit (MB) in 2 runs in a row: restarts the container and reports it
# Messages go through the Telegram bot of unas-monitor (/etc/unas-monitor.conf),
# if set up. With LoxBerry's MQTT gateway (container "loxberry") it also
# publishes the values to MQTT (topic unas/speicher) with Home Assistant MQTT
# discovery: device "UNAS Pro" with Home Assistant's RAM, swap and total, and
# the NAS's available memory and swap use, so they get a history graph. The
# values go as UDP to the gateway inside the container (no broker login here).
# Settings: /etc/ha-mem-guard.conf. State in /run/ha-mem-guard (RAM), output to
# the journal (RAM). On the UNAS: ha-mem-guard --status.
set -Eeuo pipefail
usage="usage: $0 root@<UNAS-IP> [--limit <MB>] [--warn <MB>] [--no-mqtt] | --remove"
target=${1:?$usage}
shift
limit=1200 warn=900 mqtt=loxberry remove=false
while (( $# )); do
    case "$1" in
        --limit) limit=${2:?$usage}; shift ;;
        --warn) warn=${2:?$usage}; shift ;;
        --no-mqtt) mqtt= ;;
        --remove) remove=true ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[[ "$limit" =~ ^[0-9]+$ && "$warn" =~ ^[0-9]+$ ]] && (( limit >= 600 && limit <= 3000 && warn >= 400 && warn < limit )) \
    || { echo "--limit 600-3000, --warn 400 up to below the limit (MB)" >&2; exit 2; }
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

remote "LIMIT='$limit' WARN='$warn' MQTT='$mqtt' REMOVE='$remove' bash -s" <<'EOF'
set -euo pipefail
if [ "$REMOVE" = true ]; then
    systemctl disable --now ha-mem-guard.timer >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/ha-mem-guard.service /etc/systemd/system/ha-mem-guard.timer \
          /usr/local/sbin/ha-mem-guard /etc/ha-mem-guard.conf
    rm -rf /run/ha-mem-guard
    systemctl daemon-reload
    echo "ha-mem-guard removed (the MQTT entities disappear in Home Assistant once deleted there)"
    exit 0
fi

cat > /usr/local/sbin/ha-mem-guard <<'SH'
#!/bin/bash
# Watches the memory of the Home Assistant container: early warning, restart
# above a limit, values to MQTT (installed by
# extras/unas-apps/homeassistant/install-mem-guard.sh).
#   ha-mem-guard            check (timer, every 2 min)
#   ha-mem-guard --status   print the current use and the thresholds
set -uo pipefail
umask 077
CONTAINER=homeassistant
PATTERN='^python3 -P -m homeassistant'   # the main process of the official image
LIMIT_MB=1200
WARN_MB=900
RUNS=2                                  # runs in a row above the limit before acting
MQTT_CONTAINER=loxberry                 # LoxBerry's MQTT gateway takes UDP on 11884; empty: off
STATE=/run/ha-mem-guard
[ -r /etc/ha-mem-guard.conf ] && . /etc/ha-mem-guard.conf
TELEGRAM_TOKEN='' TELEGRAM_CHAT_ID='' NAME=$(hostname)
[ -r /etc/unas-monitor.conf ] && . /etc/unas-monitor.conf
DOCKER=/usr/local/bin/docker

send() {   # send <text>: journal, and Telegram if unas-monitor has it set up
    echo "$1"
    [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ] || return 0
    q() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }
    # token and chat id never on a command line: curl reads its config from stdin
    { printf 'url = %s\n' "$(q "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage")"
      printf 'data-urlencode = %s\n' "$(q "chat_id=$TELEGRAM_CHAT_ID")" "$(q "text=$1")"
    } | curl -s --max-time 10 -o /dev/null -K - || echo "Telegram: Senden fehlgeschlagen" >&2
}

mqtt() {   # mqtt <json message>...: one UDP datagram each to the gateway in the container
    [ -n "$MQTT_CONTAINER" ] || return 0
    "$DOCKER" exec "$MQTT_CONTAINER" bash -c \
        'for m in "$@"; do printf "%s" "$m" > /dev/udp/127.0.0.1/11884; done' _ "$@" >/dev/null 2>&1 || true
}

discovery() {   # Home Assistant MQTT discovery, retained; once per boot
    local dev='{"identifiers":["unas_pro"],"name":"UNAS Pro","manufacturer":"Ubiquiti","model":"UNVR (als UNAS)"}'
    local msgs=() id name key unit cls icon cfg
    while IFS='|' read -r id name key unit cls icon; do
        cfg="{\"name\":\"$name\",\"unique_id\":\"unas_$id\",\"default_entity_id\":\"sensor.unas_$id\",\"state_topic\":\"unas/speicher\","
        cfg+="\"value_template\":\"{{ value_json.$key }}\",\"unit_of_measurement\":\"$unit\",\"state_class\":\"measurement\","
        cfg+="\"expire_after\":600,\"icon\":\"$icon\",${cls:+\"device_class\":\"$cls\",}\"device\":$dev}"
        msgs+=("$(jq -cn --arg t "homeassistant/sensor/unas_$id/config" --arg v "$cfg" '{topic:$t,value:$v,retain:true}')")
    done <<'LIST'
ha_ram|Home Assistant RAM|ha_ram|MB|data_size|mdi:memory
ha_swap|Home Assistant Swap|ha_swap|MB|data_size|mdi:swap-horizontal
ha_speicher|Home Assistant Speicher|ha_gesamt|MB|data_size|mdi:home-assistant
ram_frei|Arbeitsspeicher frei|ram_frei|MB|data_size|mdi:memory
swap_belegt|Swap belegt|swap_pct|%||mdi:swap-horizontal
LIST
    mqtt "${msgs[@]}"
}

pid=$(pgrep -f "$PATTERN" | head -1)
read -r avail swapt swapf < <(awk '/^MemAvailable/ {a=$2} /^SwapTotal/ {t=$2} /^SwapFree/ {f=$2}
                                   END {print int(a/1024), int(t/1024), int(f/1024)}' /proc/meminfo)
swappct=$(( swapt > 0 ? (swapt - swapf) * 100 / swapt : 0 ))
rss=0 swap=0
if [ -n "$pid" ]; then
    rss=$(awk '/^VmRSS/ {print int($2 / 1024)}' "/proc/$pid/status" 2>/dev/null)
    swap=$(awk '/^VmSwap/ {print int($2 / 1024)}' "/proc/$pid/status" 2>/dev/null)
fi
used=$(( ${rss:-0} + ${swap:-0} ))
if [ "${1:-}" = --status ]; then
    [ -n "$pid" ] && echo "Home Assistant: $rss MB RAM + $swap MB Swap = $used MB (Warnung ab $WARN_MB MB, Neustart ab $LIMIT_MB MB)" \
                  || echo "Home Assistant läuft nicht"
    echo "NAS: $avail MB Arbeitsspeicher verfügbar, Swap $swappct % belegt"
    exit 0
fi

mkdir -p "$STATE"
[ -f "$STATE/discovery" ] || { discovery; touch "$STATE/discovery"; }
[ -n "$pid" ] && mqtt "$(jq -cn --argjson r "$rss" --argjson s "$swap" --argjson g "$used" --argjson a "$avail" \
    --argjson p "$swappct" '{topic:"unas/speicher",value:({ha_ram:$r,ha_swap:$s,ha_gesamt:$g,ram_frei:$a,swap_pct:$p}|tojson)}')"
[ -n "$pid" ] || exit 0

if (( used > WARN_MB )); then
    if [ ! -f "$STATE/warned" ]; then
        touch "$STATE/warned"
        send "⚠️ $NAME: Home Assistant braucht $used MB ($rss MB RAM + $swap MB Swap). Warnschwelle $WARN_MB MB, Neustart ab $LIMIT_MB MB."
    fi
elif [ -f "$STATE/warned" ] && (( used < WARN_MB - 100 )); then
    rm -f "$STATE/warned"
    send "✅ $NAME: Home Assistant wieder bei $used MB."
fi

count=0; read -r count < "$STATE/over" 2>/dev/null || count=0
if (( used <= LIMIT_MB )); then
    echo 0 > "$STATE/over"
    exit 0
fi
count=$(( count + 1 )); echo "$count" > "$STATE/over"
echo "Home Assistant über der Grenze: $rss MB RAM + $swap MB Swap = $used MB > $LIMIT_MB MB ($count/$RUNS)"
(( count < RUNS )) && exit 0

echo 0 > "$STATE/over"
rm -f "$STATE/warned"
if "$DOCKER" restart "$CONTAINER" >/dev/null 2>&1; then
    send "♻️ $NAME: Home Assistant neu gestartet – es brauchte $used MB ($rss MB RAM + $swap MB Swap, Grenze $LIMIT_MB MB)."
else
    send "⚠️ $NAME: Home Assistant braucht $used MB (Grenze $LIMIT_MB MB), der Neustart ist fehlgeschlagen."
fi
SH
chmod 755 /usr/local/sbin/ha-mem-guard
printf '# Home Assistant: RAM + swap in MB (install-mem-guard.sh)\nLIMIT_MB=%s\nWARN_MB=%s\nMQTT_CONTAINER=%s\n' \
    "$LIMIT" "$WARN" "$MQTT" > /etc/ha-mem-guard.conf
rm -f /run/ha-mem-guard/discovery   # publish the discovery again on the next run

cat > /etc/systemd/system/ha-mem-guard.service <<'UNIT'
[Unit]
Description=Watch Home Assistant's memory (warn, restart above a limit, MQTT)
After=unas-docker.service

[Service]
Type=oneshot
Nice=19
ExecStart=/usr/local/sbin/ha-mem-guard
UNIT
cat > /etc/systemd/system/ha-mem-guard.timer <<'UNIT'
[Unit]
Description=Check Home Assistant's memory every 2 minutes

[Timer]
OnBootSec=10min
OnUnitActiveSec=2min
AccuracySec=10s

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now ha-mem-guard.timer >/dev/null 2>&1
/usr/local/sbin/ha-mem-guard
/usr/local/sbin/ha-mem-guard --status
systemctl is-active ha-mem-guard.timer
EOF
