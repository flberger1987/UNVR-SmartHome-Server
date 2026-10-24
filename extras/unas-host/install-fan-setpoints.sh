#!/bin/bash
# Cooler set points for the fan controller of a converted UNVR (run on the Mac).
#
#   extras/unas-host/install-fan-setpoints.sh root@<UNAS-IP> [--cpu 75] [--hdd 44]
#   extras/unas-host/install-fan-setpoints.sh root@<UNAS-IP> --reset
#
# The fans are run by Ubiquiti's uhwd (package ustd): a PID controller per
# temperature group, with the board's defaults from ustd.statusdb.config. The
# UNVR4 (board ea1a) keeps the CPU at 83 °C and the drives at 48 °C with the
# fans at ~23 % (~1,800 rpm); there is no profile to pick (UniFi Drive's fan
# mode: "the fan control is not allow in this console"), and a PWM value
# written to the hwmon device is taken back within seconds.
#
# What uhwd uses is config.fan in ustd's status database (usdbd). This writes
# /etc/ustd/fan.conf, the board's default config with only the CPU and drive
# set points changed (ustd reads an override from there), and installs
# unas-fan-config.service, which puts that file into config.fan whenever
# usdbd starts, so the set points also hold after a reboot or a restart of
# Ubiquiti's daemons. --reset removes both and restores the defaults.
#
# Measured 2026-10-24 with 75/44 under load: fans ~45-60 % (4,200-5,500 rpm),
# CPU 88 -> 78 °C within two minutes; the drives follow over half an hour.
set -Eeuo pipefail
usage="usage: $0 root@<UNAS-IP> [--cpu <°C>] [--hdd <°C>] | --reset"
target=${1:?$usage}
shift
cpu=75 hdd=44 reset=false
while (( $# )); do
    case "$1" in
        --cpu) cpu=${2:?$usage}; shift ;;
        --hdd) hdd=${2:?$usage}; shift ;;
        --reset) reset=true ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[[ "$cpu" =~ ^[0-9]{2}$ && "$hdd" =~ ^[0-9]{2}$ ]] && (( cpu >= 60 && cpu <= 90 && hdd >= 35 && hdd <= 55 )) \
    || { echo "--cpu 60-90, --hdd 35-55 (°C)" >&2; exit 2; }
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

remote "CPU='$cpu' HDD='$hdd' RESET='$reset' bash -s" <<'EOF'
set -euo pipefail
python3 -c 'import ustd.statusdb.sdb_client, ustd.statusdb.config' 2>/dev/null \
    || { echo 'no ustd on this host (not a converted UNVR?)' >&2; exit 1; }

cat > /usr/local/sbin/unas-fan-config <<'PY'
#!/usr/bin/python3
# Put /etc/ustd/fan.conf into config.fan of ustd's status database, which the
# fan controller in uhwd follows (installed by install-fan-setpoints.sh).
import json, sys, threading, time
from ustd.statusdb.sdb_client import SDBClient

def client():
    c = SDBClient()
    threading.Thread(target=c.run, daemon=True).start()
    for _ in range(240):   # usdbd may still be starting
        if c.get("config"):
            return c
        time.sleep(0.5)
    sys.exit("status database not ready")

try:
    want = json.load(open("/etc/ustd/fan.conf"))
except FileNotFoundError:
    sys.exit(0)
if client().get("config.fan") == want:
    print("fan set points already active")
    sys.exit(0)
client().update("config.fan", want)
for _ in range(20):
    time.sleep(0.5)
    if client().get("config.fan") == want:
        print("fan set points applied:", json.dumps(want.get("PID", want)))
        sys.exit(0)
sys.exit("config.fan did not take the new values")
PY
chmod 755 /usr/local/sbin/unas-fan-config

cat > /etc/systemd/system/unas-fan-config.service <<'UNIT'
[Unit]
Description=Fan set points from /etc/ustd/fan.conf into ustd's status database
After=usdbd.service uhwd.service
PartOf=usdbd.service
ConditionPathExists=/etc/ustd/fan.conf

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/unas-fan-config

[Install]
WantedBy=usdbd.service
UNIT
systemctl daemon-reload

if [ "$RESET" = true ]; then
    rm -f /etc/ustd/fan.conf
    systemctl disable --now unas-fan-config.service >/dev/null 2>&1 || true
    python3 - <<'PY'
import json, threading, time
from ustd.statusdb.config import get_default_fan_config
from ustd.statusdb.sdb_client import SDBClient
c = SDBClient(); threading.Thread(target=c.run, daemon=True).start()
for _ in range(60):
    if c.get("config"): break
    time.sleep(0.5)
c.update("config.fan", get_default_fan_config()); time.sleep(2)
print("fan set points back to the defaults:", json.dumps(get_default_fan_config().get("PID")))
PY
    exit 0
fi

# the board's defaults, only the set points changed
python3 - <<'PY'
import json, os
from ustd.statusdb.config import get_default_fan_config
cfg = get_default_fan_config()
pid = cfg.get("PID") or {}
if cfg.get("calc_type", "pid") != "pid" or "cpu" not in pid:
    raise SystemExit("this board's fan controller has no CPU PID set point: %s" % json.dumps(cfg)[:300])
pid["cpu"][0] = int(os.environ["CPU"])
if "hdd" in pid:
    pid["hdd"][0] = int(os.environ["HDD"])
with open("/etc/ustd/fan.conf.new", "w") as f:
    json.dump(cfg, f)
os.chmod("/etc/ustd/fan.conf.new", 0o644)
os.replace("/etc/ustd/fan.conf.new", "/etc/ustd/fan.conf")
print("wrote /etc/ustd/fan.conf:", json.dumps(pid))
PY
systemctl enable unas-fan-config.service >/dev/null 2>&1
systemctl restart unas-fan-config.service
journalctl -u unas-fan-config.service -n 1 --no-pager -o cat
EOF
