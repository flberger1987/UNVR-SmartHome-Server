#!/bin/bash
# An extra MQTT user on LoxBerry's Mosquitto broker, e.g. for Home Assistant
# (run on the Mac). Prints only the new password on stdout, so it can go
# straight to the clipboard:
#
#   extras/unas-apps/loxberry/mqtt-user.sh root@<UNAS-IP> homeassistant | pbcopy
#
# Running it again gives the user a new password. LoxBerry rewrites its
# password file with only its own broker user whenever the MQTT settings are
# saved; the extra users (stored as hashes in config/system/mosquitto/
# extra_users in the LoxBerry volume) are put back by a path unit
# (mosq-extra-users.path) that watches that file, and Mosquitto reloads.
set -Eeuo pipefail
target=${1:?usage: $0 root@<UNAS-IP> <user>}
user=${2:?usage: $0 root@<UNAS-IP> <user>}
[[ "$user" =~ ^[a-z][a-z0-9_-]{2,31}$ && "$user" != loxberry ]] || { echo "user: lower-case letters, digits, - and _ (not loxberry)" >&2; exit 2; }
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

remote "docker exec -i -e U='$user' loxberry bash -s" <<'EOF'
set -euo pipefail
X=/opt/loxberry/config/system/mosquitto/extra_users
[ -e $X ] || { touch $X; chown root:root $X; chmod 600 $X; }
cat > /usr/local/sbin/mosq-extra-users <<'S'
#!/bin/bash
# Extra Mosquitto users beyond LoxBerry's own broker user: LoxBerry rewrites
# /etc/mosquitto/conf.d/mosq_passwd with only its user whenever the MQTT
# settings are saved; this puts the lines from extra_users (user:hash) back
# and lets Mosquitto reload. Run by mosq-extra-users.path on every rewrite.
set -u
X=/opt/loxberry/config/system/mosquitto/extra_users P=/etc/mosquitto/conf.d/mosq_passwd
[ -s "$X" ] && [ -f "$P" ] || exit 0
changed=0
while IFS= read -r line; do
    u=${line%%:*}; [ -n "$u" ] || continue
    if ! grep -q -x -F "$line" "$P"; then
        grep -v "^$u:" "$P" > "$P.new" || true; echo "$line" >> "$P.new"
        cat "$P.new" > "$P"; rm -f "$P.new"; changed=1
    fi
done < "$X"
(( changed )) && { pkill -HUP -x mosquitto && echo "mosquitto: users reloaded"; }
exit 0
S
chmod 755 /usr/local/sbin/mosq-extra-users
cat > /etc/systemd/system/mosq-extra-users.service <<'UNIT'
[Unit]
Description=Extra Mosquitto users back into LoxBerry's password file
After=mosquitto.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/mosq-extra-users

[Install]
WantedBy=multi-user.target
UNIT
cat > /etc/systemd/system/mosq-extra-users.path <<'UNIT'
[Unit]
Description=Watch LoxBerry's Mosquitto password file

[Path]
PathChanged=/etc/mosquitto/conf.d/mosq_passwd

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now mosq-extra-users.path >/dev/null 2>&1
systemctl enable mosq-extra-users.service >/dev/null 2>&1
# the user with a new random password; only its hash is stored
pw=$(head -c 48 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 24)
t=$(mktemp); trap 'rm -f "$t"' EXIT
mosquitto_passwd -b -c "$t" "$U" "$pw" 2>/dev/null
{ grep -v "^$U:" $X || true; cat "$t"; } > $X.new && chmod 600 $X.new && mv $X.new $X
/usr/local/sbin/mosq-extra-users >&2
echo "MQTT user $U set (broker port 1883 on LoxBerry's address)" >&2
printf '%s' "$pw"
EOF
