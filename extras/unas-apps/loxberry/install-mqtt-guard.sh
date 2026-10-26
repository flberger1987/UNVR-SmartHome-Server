#!/bin/bash
# Guard for LoxBerry's MQTT gateway on the UNAS (run on the Mac).
#
#   extras/unas-apps/loxberry/install-mqtt-guard.sh root@<UNAS-IP>
#   extras/unas-apps/loxberry/install-mqtt-guard.sh root@<UNAS-IP> --remove
#
# The gateway (mqttgateway.pl) relays MQTT to the Miniserver over UDP. When the
# broker drops its connection (seen 2026-10-25: the NAS swapped hard, the
# gateway missed its keepalive pings, Mosquitto "exceeded timeout"), it
# reconnects by itself but without its subscriptions: it still publishes what
# the Miniserver sends, but relays nothing back, not even its own keepalive.
# The process keeps running, so nothing restarts it; the Miniserver only sees
# frozen values ("LoxBerry Störung (MQTT)").
#
# Installs /usr/local/sbin/loxberry-mqtt-guard and loxberry-mqtt-guard.timer
# (every minute, Nice 19). Each run looks up the gateway process (visible on
# the host) and its TCP connection to the broker (port 1883) in the
# container's network namespace:
#   - the same process on a new connection: it reconnected; with
#     Net::MQTT::Simple up to 1.32-3LB (LoxBerry 4.0.0.x, fixed in 4.0.1.0)
#     its subscriptions are gone -> restart the gateway
#   - no connection, or no gateway process, in 3 runs in a row -> restart it
# Only the gateway restarts, not the broker (LoxBerry's "restartgateway" also
# restarts Mosquitto, which drops every client); at most once in 10 minutes.
# Each restart is reported through the Telegram bot of unas-monitor
# (/etc/unas-monitor.conf), if set up. State in /run/loxberry-mqtt-guard (RAM),
# output to the journal (RAM). On the UNAS: loxberry-mqtt-guard --status.
set -Eeuo pipefail
usage="usage: $0 root@<UNAS-IP> [--remove]"
target=${1:?$usage}
shift
remove=false
while (( $# )); do
    case "$1" in
        --remove) remove=true ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

remote "REMOVE='$remove' bash -s" <<'EOF'
set -euo pipefail
if [ "$REMOVE" = true ]; then
    systemctl disable --now loxberry-mqtt-guard.timer >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/loxberry-mqtt-guard.service /etc/systemd/system/loxberry-mqtt-guard.timer \
          /usr/local/sbin/loxberry-mqtt-guard
    rm -rf /run/loxberry-mqtt-guard
    systemctl daemon-reload
    echo "loxberry-mqtt-guard removed"
    exit 0
fi

cat > /usr/local/sbin/loxberry-mqtt-guard <<'SH'
#!/bin/bash
# Restarts LoxBerry's MQTT gateway when it lost its broker connection or
# reconnected without its subscriptions (installed by
# extras/unas-apps/loxberry/install-mqtt-guard.sh).
#   loxberry-mqtt-guard            check (timer, every minute)
#   loxberry-mqtt-guard --status   print the gateway and its broker connection
set -uo pipefail
umask 077
CONTAINER=loxberry
PATTERN='^/usr/bin/perl /opt/loxberry/sbin/mqttgateway\.pl|/opt/loxberry/sbin/mqtt_gateway\.py'
RUNS=3            # runs in a row without a connection or process before acting
PAUSE=600         # seconds between two restarts at least
STATE=/run/loxberry-mqtt-guard
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

broker_ports() {   # broker_ports <pid>: local ports of its established connections to port 1883
    local pid=$1 inodes
    inodes=$(for fd in /proc/"$pid"/fd/*; do readlink "$fd"; done 2>/dev/null | sed -n 's/^socket:\[\([0-9]*\)\]$/\1/p' | sort -u)
    [ -n "$inodes" ] || return 0
    awk -v ids="$(echo $inodes)" 'BEGIN { n = split(ids, a, " "); for (i = 1; i <= n; i++) want[a[i]] = 1 }
         FNR > 1 && $4 == "01" && $3 ~ /:075B$/ && ($10 in want) { split($2, l, ":"); print l[2] }' \
        /proc/"$pid"/net/tcp /proc/"$pid"/net/tcp6 2>/dev/null \
        | while read -r hex; do echo $(( 16#$hex )); done | sort -n | paste -sd,
}

loses_subscriptions() {   # loses_subscriptions <pid>: does this gateway lose its subscriptions on a reconnect?
    # Net::MQTT::Simple up to 1.32-3LB (LoxBerry 4.0.0.x) reset the wrong field on reconnect and sent no
    # SUBSCRIBE; fixed in 1.32-4LB (LoxBerry 4.0.1.0, upstream 1.33). The Python gateway (V2) builds a new
    # client and subscribes on every connect. Unknown versions count as affected.
    local v
    grep -q mqttgateway.pl "/proc/$1/cmdline" 2>/dev/null || return 1
    v=$(sed -n "s/^our \$VERSION = '\([^']*\)'.*/\1/p" "/proc/$1/root/opt/loxberry/libs/perllib/Net/MQTT/Simple.pm" 2>/dev/null)
    [[ "$v" =~ ^1\.([0-9]+)(-([0-9]+)LB)?$ ]] || return 0
    (( BASH_REMATCH[1] < 32 )) && return 0
    (( BASH_REMATCH[1] > 32 )) && return 1
    [ -z "${BASH_REMATCH[3]}" ] && return 0
    (( BASH_REMATCH[3] <= 3 ))
}

restart_gateway() {   # restart_gateway <reason>: only the gateway, as LoxBerry's mqtt-handler.pl does for V1
    local reason=$1 now last=0
    now=$(date +%s); { read -r last < "$STATE/restarted"; } 2>/dev/null || last=0
    if (( now - last < PAUSE )); then
        echo "$reason - kein Neustart, der letzte war vor $(( now - last )) s"
        return 0
    fi
    echo "$now" > "$STATE/restarted"
    if "$DOCKER" exec "$CONTAINER" bash -c '
        v=$(jq -r ".Mqtt.Gatewayversion // 1" /opt/loxberry/config/system/general.json 2>/dev/null)
        if [ "$v" = 2 ]; then
            # V2 (Python) has more to set up; LoxBerry restarts the broker with it
            /opt/loxberry/sbin/mqtt-handler.pl action=restartgateway >/dev/null 2>&1
        else
            pkill mqttgateway.pl; sleep 2
            su loxberry -c "/opt/loxberry/sbin/mqttgateway.pl > /dev/null 2>&1 &"
        fi' >/dev/null 2>&1; then
        send "♻️ $NAME: LoxBerry-MQTT-Gateway neu gestartet – $reason. Ohne Neustart hätte der Miniserver keine MQTT-Werte mehr bekommen."
    else
        send "⚠️ $NAME: LoxBerry-MQTT-Gateway – $reason, der Neustart ist fehlgeschlagen."
    fi
    rm -f "$STATE/seen" "$STATE/missing"
}

"$DOCKER" container inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true || exit 0
pid=$(pgrep -f "$PATTERN" | head -1)
ports=''
[ -n "$pid" ] && ports=$(broker_ports "$pid")
if [ "${1:-}" = --status ]; then
    if [ -n "$pid" ]; then
        echo "MQTT-Gateway: Prozess $pid seit $(ps -o lstart= -p "$pid"), Broker-Verbindung: ${ports:-keine}"
    else
        echo "MQTT-Gateway läuft nicht"
    fi
    seen='' last=''
    { read -r seen < "$STATE/seen"; read -r last < "$STATE/restarted"; } 2>/dev/null
    echo "zuletzt gesehen: ${seen:-–}; letzter Neustart durch den Wächter: $([ -n "$last" ] && date -d @"$last" '+%F %T' || echo –)"
    exit 0
fi

mkdir -p "$STATE"
if [ -z "$pid" ] || [ -z "$ports" ]; then
    count=0; { read -r count < "$STATE/missing"; } 2>/dev/null || count=0
    count=$(( count + 1 )); echo "$count" > "$STATE/missing"
    what=$([ -z "$pid" ] && echo "der Prozess fehlt" || echo "keine Verbindung zum Broker")
    echo "MQTT-Gateway: $what ($count/$RUNS)"
    (( count >= RUNS )) && restart_gateway "$what seit $RUNS min"
    exit 0
fi
rm -f "$STATE/missing"
seen_pid='' seen_ports=''
{ read -r seen_pid seen_ports < "$STATE/seen"; } 2>/dev/null || true
if [ "$seen_pid" = "$pid" ] && [ -n "$seen_ports" ] && [ "$seen_ports" != "$ports" ]; then
    if loses_subscriptions "$pid"; then
        restart_gateway "es hatte sich beim Broker neu verbunden (Port $seen_ports → $ports) und dabei seine Abos verloren"
        exit 0
    fi
    echo "MQTT-Gateway hat sich neu verbunden (Port $seen_ports → $ports); seine Bibliothek abonniert neu, kein Neustart"
fi
echo "$pid $ports" > "$STATE/seen"
SH
chmod 755 /usr/local/sbin/loxberry-mqtt-guard

cat > /etc/systemd/system/loxberry-mqtt-guard.service <<'UNIT'
[Unit]
Description=Restart LoxBerry's MQTT gateway when it reconnected without its subscriptions
After=unas-docker.service

[Service]
Type=oneshot
Nice=19
ExecStart=/usr/local/sbin/loxberry-mqtt-guard
UNIT
cat > /etc/systemd/system/loxberry-mqtt-guard.timer <<'UNIT'
[Unit]
Description=Check LoxBerry's MQTT gateway every minute

[Timer]
OnBootSec=5min
OnUnitActiveSec=1min
AccuracySec=10s

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now loxberry-mqtt-guard.timer >/dev/null 2>&1
/usr/local/sbin/loxberry-mqtt-guard
/usr/local/sbin/loxberry-mqtt-guard --status
systemctl is-active loxberry-mqtt-guard.timer
EOF
