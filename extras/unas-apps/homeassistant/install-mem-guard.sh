#!/bin/bash
# Memory guard for the Home Assistant container on the UNAS (run on the Mac).
#
#   extras/unas-apps/homeassistant/install-mem-guard.sh root@<UNAS-IP> [--limit 1200]
#   extras/unas-apps/homeassistant/install-mem-guard.sh root@<UNAS-IP> --remove
#
# The UNAS kernel has no cgroups, so Docker cannot limit a container's memory.
# A Home Assistant that grows (a leaking custom integration, a map renderer)
# first fills the swap and then starves UniFi OS, Protect and their databases
# (seen 2026-10-25: MongoDB shut down uncleanly, Protect restarted).
#
# Installs /usr/local/sbin/ha-mem-guard and ha-mem-guard.timer (every 2 min,
# Nice 19). Each run adds up RAM and swap of the Home Assistant process; above
# the limit in 2 runs in a row it restarts the container and sends a message
# through the Telegram bot of unas-monitor (/etc/unas-monitor.conf), if set up.
# Settings: /etc/ha-mem-guard.conf. State in /run/ha-mem-guard (RAM), output to
# the journal (RAM). On the UNAS: ha-mem-guard --status.
set -Eeuo pipefail
usage="usage: $0 root@<UNAS-IP> [--limit <MB>] | --remove"
target=${1:?$usage}
shift
limit=1200 remove=false
while (( $# )); do
    case "$1" in
        --limit) limit=${2:?$usage}; shift ;;
        --remove) remove=true ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[[ "$limit" =~ ^[0-9]+$ ]] && (( limit >= 600 && limit <= 3000 )) || { echo "--limit 600-3000 (MB)" >&2; exit 2; }
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

remote "LIMIT='$limit' REMOVE='$remove' bash -s" <<'EOF'
set -euo pipefail
if [ "$REMOVE" = true ]; then
    systemctl disable --now ha-mem-guard.timer >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/ha-mem-guard.service /etc/systemd/system/ha-mem-guard.timer \
          /usr/local/sbin/ha-mem-guard /etc/ha-mem-guard.conf
    rm -rf /run/ha-mem-guard
    systemctl daemon-reload
    echo "ha-mem-guard removed"
    exit 0
fi

cat > /usr/local/sbin/ha-mem-guard <<'SH'
#!/bin/bash
# Restarts the Home Assistant container when it uses too much memory
# (installed by extras/unas-apps/homeassistant/install-mem-guard.sh).
#   ha-mem-guard            check (timer, every 2 min)
#   ha-mem-guard --status   print the current use and the limit
set -uo pipefail
umask 077
CONTAINER=homeassistant
PATTERN='^python3 -P -m homeassistant'   # the main process of the official image
LIMIT_MB=1200
RUNS=2                                  # runs in a row above the limit before acting
STATE=/run/ha-mem-guard
[ -r /etc/ha-mem-guard.conf ] && . /etc/ha-mem-guard.conf
TELEGRAM_TOKEN='' TELEGRAM_CHAT_ID='' NAME=$(hostname)
[ -r /etc/unas-monitor.conf ] && . /etc/unas-monitor.conf

pid=$(pgrep -f "$PATTERN" | head -1)
if [ -z "$pid" ]; then
    [ "${1:-}" = --status ] && echo "Home Assistant läuft nicht"
    exit 0
fi
rss=$(awk '/^VmRSS/ {print int($2 / 1024)}' "/proc/$pid/status" 2>/dev/null)
swap=$(awk '/^VmSwap/ {print int($2 / 1024)}' "/proc/$pid/status" 2>/dev/null)
used=$(( ${rss:-0} + ${swap:-0} ))
if [ "${1:-}" = --status ]; then
    echo "Home Assistant: $rss MB RAM + $swap MB Swap = $used MB, Grenze $LIMIT_MB MB"
    exit 0
fi

mkdir -p "$STATE"
count=0; read -r count < "$STATE/over" 2>/dev/null || count=0
if (( used <= LIMIT_MB )); then
    echo 0 > "$STATE/over"
    exit 0
fi
count=$(( count + 1 )); echo "$count" > "$STATE/over"
echo "Home Assistant über der Grenze: $rss MB RAM + $swap MB Swap = $used MB > $LIMIT_MB MB ($count/$RUNS)"
(( count < RUNS )) && exit 0

echo 0 > "$STATE/over"
if /usr/local/bin/docker restart "$CONTAINER" >/dev/null 2>&1; then
    text="♻️ $NAME: Home Assistant neu gestartet – es brauchte $used MB ($rss MB RAM + $swap MB Swap, Grenze $LIMIT_MB MB)."
else
    text="⚠️ $NAME: Home Assistant braucht $used MB (Grenze $LIMIT_MB MB), der Neustart ist fehlgeschlagen."
fi
echo "$text"
if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    q() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }
    # token and chat id never on a command line: curl reads its config from stdin
    { printf 'url = %s\n' "$(q "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage")"
      printf 'data-urlencode = %s\n' "$(q "chat_id=$TELEGRAM_CHAT_ID")" "$(q "text=$text")"
    } | curl -s --max-time 10 -o /dev/null -K - || echo "Telegram: Senden fehlgeschlagen" >&2
fi
SH
chmod 755 /usr/local/sbin/ha-mem-guard
printf '# Home Assistant: RAM + swap in MB before a restart (install-mem-guard.sh)\nLIMIT_MB=%s\n' "$LIMIT" > /etc/ha-mem-guard.conf

cat > /etc/systemd/system/ha-mem-guard.service <<'UNIT'
[Unit]
Description=Restart Home Assistant when it uses too much memory
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
/usr/local/sbin/ha-mem-guard --status
systemctl is-active ha-mem-guard.timer
EOF
