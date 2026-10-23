#!/bin/bash
# Install a LoxBerry plugin from a zip (run on the Mac, in a terminal).
#
#   extras/unas-apps/loxberry/install-plugin.sh [--dry-run] root@<UNAS-IP> <zip-url|plugin.zip> [container]
#
# <zip-url>   https URL of a .zip; downloaded inside the container.
# plugin.zip  local file; streamed over SSH straight into the container (nothing is
#             left on the NAS host) and checked against its SHA-256.
#
# Same as Plugin Management in the web interface: LoxBerry's plugininstall.pl,
# which asks for the SecurePIN (typed here, not echoed). plugininstall.pl only
# takes it as a command-line parameter, so it is visible in the container's
# process list while the install runs; change the PIN afterwards if that matters.
#
# --dry-run: no PIN, no install. Fetches or uploads the zip, checks that it is a
# valid zip with a plugin.cfg, prints its name and version, and removes it again.
set -Eeuo pipefail
dry=0
if [ "${1:-}" = "--dry-run" ]; then dry=1; shift; fi
usage="usage: $0 [--dry-run] root@<UNAS-IP> <zip-url|plugin.zip> [container]"
target=${1:?$usage}; src=${2:?$usage}; c=${3:-loxberry}
[[ "$c" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo 'invalid container name' >&2; exit 2; }

url=-; sum=-
if [[ "$src" == https://* ]]; then
	[[ "$src" =~ ^https://[A-Za-z0-9./_~%+-]+\.zip$ ]] || { echo 'expected an https URL of a .zip' >&2; exit 2; }
	mode=url; url=$src
elif [[ "$src" == *.zip ]]; then
	[ -f "$src" ] && [ -r "$src" ] || { echo "no such file: $src" >&2; exit 2; }
	unzip -tqq "$src" >/dev/null 2>&1 || { echo "not a valid zip: $src" >&2; exit 2; }
	mode=file
	if command -v sha256sum >/dev/null; then sum=$(sha256sum "$src" | cut -d' ' -f1)
	else sum=$(shasum -a 256 "$src" | cut -d' ' -f1); fi
else
	echo 'expected an https URL or the path of a local .zip' >&2; exit 2
fi
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

if [ $dry -eq 0 ]; then
	read -r -s -p 'LoxBerry SecurePIN: ' pin; echo
	[[ "$pin" =~ ^[A-Za-z0-9]{4,10}$ ]] || { echo 'SecurePIN: 4-10 letters or digits' >&2; exit 2; }
fi

remote "docker exec -i $c sh -c 'umask 077; cat > /root/.lb-plugin.sh'" <<'SH'
set -eu
mode=$1; url=$2; sum=$3; dry=$4
pin=
[ "$dry" = 1 ] || IFS= read -r pin
# LoxBerry's tools need its environment (PERL5LIB, LB* paths); docker exec
# does not read /etc/environment
set -a; . /etc/environment; set +a
z=$(mktemp /tmp/plugin-XXXXXX.zip)
trap 'rm -f "$z" /root/.lb-plugin.zip' EXIT
if [ "$mode" = url ]; then
	curl -fsSL -m 300 -o "$z" "$url"
	echo "downloaded $(du -h "$z" | cut -f1)"
else
	mv /root/.lb-plugin.zip "$z"
	[ "$(sha256sum "$z" | cut -d' ' -f1)" = "$sum" ] || { echo 'upload damaged (SHA-256 differs)' >&2; exit 3; }
	echo "received $(du -h "$z" | cut -f1), SHA-256 ok"
fi
chmod 644 "$z"
unzip -tqq "$z" >/dev/null || { echo 'not a valid zip' >&2; exit 3; }
cfg=$(unzip -Z1 "$z" | grep -E '(^|/)plugin\.cfg$' | head -n 1)
[ -n "$cfg" ] || { echo 'no plugin.cfg in the zip - not a LoxBerry plugin' >&2; exit 3; }
unzip -p "$z" "$cfg" | tr -d '\r' | awk '/^\[/ { s = $0 } s == "[PLUGIN]" && /^(TITLE|NAME|FOLDER|VERSION)=/ { print "  " $0 }'
if [ "$dry" = 1 ]; then
	echo "dry run: not installed"
	exit 0
fi
perl /opt/loxberry/sbin/plugininstall.pl action=install file="$z" pin="$pin" 2>&1 | tail -n 8
echo "--- installed plugins"
python3 -c '
import json
d = json.load(open("/opt/loxberry/data/system/plugindatabase.json"))
for p in d.get("plugins", {}).values():
    print(" ", p.get("title") or p.get("name"), p.get("version"))'
SH

if [ "$mode" = file ]; then
	remote "docker exec -i $c sh -c 'umask 077; cat > /root/.lb-plugin.zip'" < "$src"
fi
run="bash /root/.lb-plugin.sh $mode \"$url\" $sum $dry; rc=\$?; rm -f /root/.lb-plugin.sh /root/.lb-plugin.zip; exit \$rc"
if [ $dry -eq 1 ]; then
	remote "docker exec -i $c sh -c '$run'" </dev/null
else
	printf '%s\n' "$pin" | remote "docker exec -i $c sh -c '$run'"
	unset pin
fi
