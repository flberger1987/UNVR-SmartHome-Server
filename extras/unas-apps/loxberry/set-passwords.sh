#!/bin/bash
# Set LoxBerry's admin password (web interface, system user loxberry, Samba)
# and optionally the SecurePIN (run on the Mac, in a terminal).
#
#   extras/unas-apps/loxberry/set-passwords.sh root@<UNAS-IP> [container]
#
# LoxBerry's own page needs the old password and the old SecurePIN; the
# installer in the image build set random ones nobody saw, so the page cannot
# change them. This sets them as root inside the container, the way LoxBerry's
# credentialshandler.pl does, and checks them afterwards. Input is not echoed
# and only travels over stdin. SSH into LoxBerry stays key-only either way.
set -Eeuo pipefail
target=${1:?usage: $0 root@<UNAS-IP> [container]}
c=${2:-loxberry}
[[ "$c" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo 'invalid container name' >&2; exit 2; }
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }
die() { echo "$*" >&2; exit 2; }

read -r -s -p 'New LoxBerry password (Enter = keep the current one): ' pw; echo
if [[ -n "$pw" ]]; then
    read -r -s -p 'Repeat password: ' pw2; echo
    [[ "$pw" == "$pw2" ]] || die 'passwords differ'
    (( ${#pw} >= 8 )) || die 'password too short (min. 8)'
    [[ "$pw" =~ ^[^\'\"\\[:space:]]+$ ]] || die "no quotes, backslashes or spaces (LoxBerry's scripts cannot handle them)"
fi
read -r -s -p 'New SecurePIN (4-10 letters/digits, Enter = keep the current one): ' pin; echo
if [[ -n "$pin" ]]; then
    read -r -s -p 'Repeat SecurePIN: ' pin2; echo
    [[ "$pin" == "$pin2" ]] || die 'PINs differ'
    [[ "$pin" =~ ^[A-Za-z0-9]{4,10}$ ]] || die 'SecurePIN: 4-10 letters or digits'
fi
[[ -n "$pw" || -n "$pin" ]] || die 'nothing to change'

# helper inside the container; the secrets follow on its stdin
remote "docker exec -i $c sh -c 'umask 077; cat > /root/.lb-setpw.sh'" <<'SH'
set -eu
IFS= read -r pw
IFS= read -r pin || true
h=/opt/loxberry/config/system
if [ -n "$pw" ]; then
    printf 'loxberry:%s\n' "$pw" | chpasswd -c SHA512
    printf '%s\n%s\n' "$pw" "$pw" | smbpasswd -a -s loxberry >/dev/null 2>&1 || echo "Samba password not set (Samba not in use)"
    printf '%s\n' "$pw" | htpasswd -i -c "$h/htusers.dat" loxberry 2>/dev/null
    chown loxberry:loxberry "$h/htusers.dat"; chmod 600 "$h/htusers.dat"
fi
if [ -n "$pin" ]; then
    printf '%s\n' "$pin" | perl -e '@c=("a".."z","A".."Z",0..9,".","/"); $s=$c[rand @c].$c[rand @c]; $p=<STDIN>; chomp $p; print crypt($p,$s)' > "$h/securepin.dat.new"
    mv "$h/securepin.dat.new" "$h/securepin.dat"; chown loxberry:loxberry "$h/securepin.dat"; chmod 644 "$h/securepin.dat"
fi
# checks (same methods as LoxBerry)
if [ -n "$pw" ]; then
    printf '%s\n' "$pw" | htpasswd -v -i "$h/htusers.dat" loxberry >/dev/null 2>&1 && echo "web interface password: OK" || echo "web interface password: FAILED"
    printf '%s\n' "$pw" | perl -e '$p=<STDIN>; chomp $p; $h=(getpwnam("loxberry"))[1]; exit(crypt($p,$h) eq $h ? 0 : 1)' && echo "system password: OK" || echo "system password: FAILED"
fi
if [ -n "$pin" ]; then
    printf '%s\n' "$pin" | perl -e '$p=<STDIN>; chomp $p; open F,"<","/opt/loxberry/config/system/securepin.dat"; $s=<F>; chomp $s; exit(crypt($p,$s) eq $s ? 0 : 1)' && echo "SecurePIN: OK" || echo "SecurePIN: FAILED"
fi
SH
printf '%s\n%s\n' "$pw" "$pin" | remote "docker exec -i $c sh -c 'bash /root/.lb-setpw.sh; rc=\$?; rm -f /root/.lb-setpw.sh; exit \$rc'"
unset pw pw2 pin pin2
echo "Sign in at http://<LOXBERRY_IP>/ as loxberry with the new password."
