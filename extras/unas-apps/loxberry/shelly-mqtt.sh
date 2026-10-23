#!/bin/bash
# Connect Shelly Gen2/Gen3 devices to LoxBerry's MQTT broker and forward their
# values to the Miniserver (run on the Mac, in a terminal).
#
#   extras/unas-apps/loxberry/shelly-mqtt.sh root@<UNAS-IP> <LOXBERRY_IP> <shelly-ip>...
#
# - LoxBerry: broker user "loxberry" with the password typed here, the broker
#   opened to the LAN (LoxBerry's own mqtt-handler.pl, as its MQTT page does),
#   gateway subscription "shellies/#" to the Miniserver
# - each Shelly (RPC API, no device password set): MQTT to <LOXBERRY_IP>:1883,
#   topic prefix shellies/<device id>, status and RPC notifications; then a
#   restart (the plugs are off for a few seconds and restore their last state)
# The password is not echoed and only travels over stdin.
set -Eeuo pipefail
usage="usage: $0 root@<UNAS-IP> <LOXBERRY_IP> <shelly-ip>..."
target=${1:?$usage}; lbip=${2:?$usage}; shift 2
(( $# )) || { echo "$usage" >&2; exit 2; }
ipre='^[0-9]{1,3}(\.[0-9]{1,3}){3}$'
for ip in "$lbip" "$@"; do [[ "$ip" =~ $ipre ]] || { echo "invalid address $ip" >&2; exit 2; }; done
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }
die() { echo "$*" >&2; exit 2; }

read -r -s -p 'MQTT password for LoxBerry and the Shellys: ' pw; echo
read -r -s -p 'Repeat password: ' pw2; echo
[[ "$pw" == "$pw2" ]] || die 'passwords differ'
(( ${#pw} >= 10 )) || die 'password too short (min. 10)'
[[ "$pw" =~ ^[A-Za-z0-9._~!@%^*+=-]+$ ]] || die 'allowed: letters, digits and ._~!@%^*+=-'

remote "umask 077; cat > /root/.shelly-mqtt.sh" <<'SH'
set -eu
IFS= read -r pw
lbip=$1; shift
# 1. LoxBerry: broker credentials, LAN listener, gateway subscription
printf '%s\n' "$pw" | docker exec -i loxberry python3 -c '
import json, os, sys
pw = sys.stdin.readline().rstrip("\n")
f = "/opt/loxberry/config/system/general.json"
d = json.load(open(f))
m = d.setdefault("Mqtt", {})
m["Brokeruser"] = "loxberry"; m["Brokerpass"] = pw; m["Uselocalbroker"] = "true"
m.setdefault("Brokerport", "1883")
json.dump(d, open(f + ".new", "w"), indent=1)
os.replace(f + ".new", f)
g = "/opt/loxberry/config/system/mqttgateway.json"
c = json.load(open(g))
subs = c.setdefault("subscriptions", [])
if not any(s.get("id") == "shellies/#" for s in subs):
    subs.append({"id": "shellies/#", "toMS": []})
json.dump(c, open(g + ".new", "w"), indent=1)
os.replace(g + ".new", g)
'
# LoxBerry's tools need its environment (PERL5LIB, LB* paths); docker exec
# does not read /etc/environment. restartgateway ends with a harmless
# "Can't call method write" from LoxBerry's own END block.
docker exec loxberry bash -c 'set -a; . /etc/environment; set +a
    chown loxberry:loxberry /opt/loxberry/config/system/general.json /opt/loxberry/config/system/mqttgateway.json
    chmod 600 /opt/loxberry/config/system/mqttgateway.json
    perl /opt/loxberry/sbin/mqtt-handler.pl action=mosquitto_set >/tmp/mqtt-handler.out 2>&1 || { tail -5 /tmp/mqtt-handler.out; exit 1; }
    perl /opt/loxberry/sbin/mqtt-handler.pl action=restartgateway >/dev/null 2>&1 || true
    sleep 4
    grep -q "^allow_anonymous false" /etc/mosquitto/conf.d/mosq_mqttgateway.conf || { echo "LoxBerry: broker still allows anonymous access"; exit 1; }
    if timeout 8 mosquitto_sub -h localhost -t "#" -C 1 -W 5 >/dev/null 2>&1; then echo "LoxBerry: broker accepts anonymous logins"; exit 1; fi
    ss -tln | grep -q ":1883 " && echo "LoxBerry: broker on port 1883, login required (anonymous refused)"'
# 2. Shellys
for ip in "$@"; do
    info=$(curl -s -m 8 "http://$ip/rpc/Shelly.GetDeviceInfo") || { echo "$ip: not reachable"; continue; }
    id=$(printf '%s' "$info" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["id"] if not d.get("auth_en") else "")')
    [ -n "$id" ] || { echo "$ip: device password set, skipped"; continue; }
    body=$(printf '%s\n' "$pw" | python3 -c '
import json, sys
pw = sys.stdin.readline().rstrip("\n"); lbip, dev = sys.argv[1], sys.argv[2]
print(json.dumps({"config": {"enable": True, "server": lbip + ":1883", "client_id": dev, "user": "loxberry",
    "pass": pw, "topic_prefix": "shellies/" + dev, "rpc_ntf": True, "status_ntf": True, "ssl_ca": None}}))' "$lbip" "$id")
    r=$(printf '%s' "$body" | curl -s -m 8 -H 'Content-Type: application/json' --data-binary @- "http://$ip/rpc/MQTT.SetConfig")
    case "$r" in *restart_required*) curl -s -m 8 "http://$ip/rpc/Shelly.Reboot" >/dev/null; echo "$ip ($id): MQTT set, restarting" ;;
                 *) echo "$ip ($id): MQTT.SetConfig failed: $(printf '%s' "$r" | cut -c1-120)" ;; esac
done
# 3. check
sleep 45
for ip in "$@"; do
    s=$(curl -s -m 8 "http://$ip/rpc/MQTT.GetStatus" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("connected"))' 2>/dev/null || echo "?")
    echo "$ip: MQTT connected=$s"
done
printf '%s\n' "$pw" | docker exec -i loxberry sh -c 'IFS= read -r p; timeout 20 mosquitto_sub -h localhost -u loxberry -P "$p" -t "shellies/#" -v -W 15 2>/dev/null | cut -d" " -f1 | cut -d/ -f1-3 | sort -u | head -20' | sed 's/^/received: /' || true
SH
printf '%s\n' "$pw" | remote "bash /root/.shelly-mqtt.sh $lbip $*; rc=\$?; rm -f /root/.shelly-mqtt.sh; exit \$rc"
unset pw pw2
cat <<'TXT'

Next in LoxBerry: MQTT -> Incoming overview lists the values (e.g.
shellies_<device>_status_switch:0_apower). Create virtual inputs with those
names in Loxone Config; switch a plug from Loxone with a virtual output
http://<shelly-ip>/rpc/Switch.Set?id=0&on=true (or false).
TXT
