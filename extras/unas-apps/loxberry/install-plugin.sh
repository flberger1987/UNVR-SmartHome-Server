#!/bin/bash
# Install a LoxBerry plugin from a zip URL (run on the Mac, in a terminal).
#
#   extras/unas-apps/loxberry/install-plugin.sh root@<UNAS-IP> <zip-url> [container]
#
# Same as Plugin Management in the web interface: LoxBerry's plugininstall.pl,
# which asks for the SecurePIN (typed here, not echoed).
set -Eeuo pipefail
usage="usage: $0 root@<UNAS-IP> <zip-url> [container]"
target=${1:?$usage}; url=${2:?$usage}; c=${3:-loxberry}
[[ "$url" =~ ^https://[A-Za-z0-9./_~%+-]+\.zip$ ]] || { echo 'expected an https URL of a .zip' >&2; exit 2; }
[[ "$c" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo 'invalid container name' >&2; exit 2; }
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

read -r -s -p 'LoxBerry SecurePIN: ' pin; echo
[[ "$pin" =~ ^[A-Za-z0-9]{4,10}$ ]] || { echo 'SecurePIN: 4-10 letters or digits' >&2; exit 2; }

remote "docker exec -i $c sh -c 'umask 077; cat > /root/.lb-plugin.sh'" <<'SH'
set -eu
IFS= read -r pin
url=$1
# LoxBerry's tools need its environment (PERL5LIB, LB* paths); docker exec
# does not read /etc/environment
set -a; . /etc/environment; set +a
z=$(mktemp /tmp/plugin-XXXXXX.zip)
curl -fsSL -m 300 -o "$z" "$url"
echo "downloaded $(du -h "$z" | cut -f1)"
chmod 644 "$z"
perl /opt/loxberry/sbin/plugininstall.pl action=install file="$z" pin="$pin" 2>&1 | tail -n 8
rm -f "$z"
echo "--- installed plugins"
python3 -c '
import json
d = json.load(open("/opt/loxberry/data/system/plugindatabase.json"))
for p in d.get("plugins", {}).values():
    print(" ", p.get("title") or p.get("name"), p.get("version"))'
SH
printf '%s\n' "$pin" | remote "docker exec -i $c sh -c 'bash /root/.lb-plugin.sh \"$url\"; rc=\$?; rm -f /root/.lb-plugin.sh; exit \$rc'"
unset pin
