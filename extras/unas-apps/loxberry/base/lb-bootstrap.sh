#!/usr/bin/env bash
# Adapted from github.com/leberert/loxberry-docker-arm64 (Apache-2.0, see LICENSE).
# Changes: the upstream main installer now installs LoxBerry 4 for Debian 13,
# whose systemd refuses the UNVR's cgroup v1. Pin the Debian 12 installer and
# LoxBerry 3.0.1.3 instead, and describe the faked DietPi as bookworm.
set -euo pipefail

INSTALLER_COMMIT=7234295b25fd355fef723cbb6daf00d9c14f1ee9
LOXBERRY_TAG=${LOXBERRY_TAG:-3.0.1.3}
UPSTREAM_INSTALLER="https://raw.githubusercontent.com/mschlenstedt/Loxberry_Installer/${INSTALLER_COMMIT}/install_bookworm.sh"
LOG="/var/log/loxberry-install.log"

export TERM=xterm
export DEBIAN_FRONTEND=noninteractive

log()  { echo -e "[lb-bootstrap] $*"; }
fail() { echo -e "[lb-bootstrap] ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Must run as root."

# --- 1. Install missing tools ---
log "Installing prerequisites..."
apt-get update -qq
apt-get install -y --no-install-recommends psmisc procps

# --- 2. Create loxberry user (installer expects it) ---
log "Creating loxberry user..."
groupadd -f loxberry
id loxberry &>/dev/null || useradd -m -g loxberry -s /bin/bash loxberry
# A real DietPi image ships a 'dietpi' user; the bookworm installer resets its
# password and adds loxberry to its group.
groupadd -f dietpi
id dietpi &>/dev/null || useradd -m -g dietpi -s /bin/bash dietpi
echo "loxberry:loxberry" | chpasswd
mkdir -p /opt/loxberry
chown loxberry:loxberry /opt/loxberry

# --- 3. Fake DietPi environment ---
log "Faking DietPi environment..."

mkdir -p /boot/dietpi/func

cat > /boot/dietpi/.version <<'EOF'
G_DIETPI_VERSION_CORE=9
G_DIETPI_VERSION_SUB=9
G_DIETPI_VERSION_RC=1
G_GITBRANCH='master'
G_GITOWNER='MichaIng'
EOF

cat > /boot/dietpi/.hw_model <<'EOF'
G_HW_MODEL=4
G_HW_MODEL_NAME='RPi 4 Model B (aarch64)'
G_HW_ARCH=3
G_HW_ARCH_NAME='aarch64'
G_HW_CPUID=0
G_HW_CPU_CORES=4
G_DISTRO=7
G_DISTRO_NAME='bookworm'
G_ROOTFS_DEV='/dev/root'
G_HW_UUID='loxberry-docker-arm64'
EOF

for stub in dietpi-set_software dietpi-obtain_hw_model dietpi-services; do
    cat > "/boot/dietpi/func/$stub" <<'STUBEOF'
#!/bin/bash
exit 0
STUBEOF
    chmod +x "/boot/dietpi/func/$stub"
done

# dietpi-software is DietPi's package front end; map the IDs the bookworm
# installer asks for to plain apt (105 = OpenSSH server, 9 = Node.js).
cat > /boot/dietpi/dietpi-software <<'STUBEOF'
#!/bin/bash
[ "$1" = install ] || exit 0
shift
for id in "$@"; do
    case "$id" in
        105) apt-get install -y --no-install-recommends openssh-server ;;
        9)   apt-get install -y --no-install-recommends nodejs npm ;;
    esac
done
exit 0
STUBEOF
chmod +x /boot/dietpi/dietpi-software

# Prevent reboot/shutdown during build
ln -sf /bin/true /usr/local/sbin/reboot
ln -sf /bin/true /usr/local/sbin/shutdown

# --- 4. Stub systemctl during build ---
cat > /usr/local/sbin/systemctl-stub <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x /usr/local/sbin/systemctl-stub

if [ "$(cat /proc/1/comm 2>/dev/null)" != "systemd" ]; then
    log "systemd not running (build phase) — stubbing systemctl"
    dpkg-divert --local --rename --add /usr/bin/systemctl
    ln -sf /usr/local/sbin/systemctl-stub /usr/bin/systemctl
fi

# --- 5. Fake /proc/mounts to avoid tmpfs check ---
log "Faking tmpfs mounts check..."
# The installer checks for stale tmpfs mounts — we remove them
umount -a -t tmpfs 2>/dev/null || true

# --- 6. Download and patch the upstream installer ---
log "Downloading upstream installer..."
TMP=$(mktemp)
curl -fsSL "$UPSTREAM_INSTALLER" -o "$TMP" \
    || fail "Could not download $UPSTREAM_INSTALLER"

log "Patching installer..."
# Remove the tmpfs mount check that fails in Docker
sed -i '/old mounts of tmpfs/,/exit 1/d' "$TMP"
sed -i '/old mounts of tmpfs/d' "$TMP"

# Remove the "reboot and start again" block
sed -i '/Please reboot and start installation again/d' "$TMP"

# --- 7. Run the installer ---
log "Running LoxBerry installer (full log: $LOG)"
mkdir -p "$(dirname "$LOG")"

bash "$TMP" -t "$LOXBERRY_TAG" 2>&1 | tee "$LOG" || true
# The installer's FAIL() only prints, so judge the result instead of its messages.
grep 'FAILED' "$LOG" >&2 || true
[[ "$(jq -r '.Base.Version' /opt/loxberry/config/system/general.json.default 2>/dev/null)" == "$LOXBERRY_TAG" ]] \
    || fail "LoxBerry $LOXBERRY_TAG is not installed"
[[ -d /etc/php/7.4/apache2 && -d /opt/loxberry/webfrontend/htmlauth && -d /opt/loxberry/libs/perllib ]] \
    || fail 'LoxBerry PHP, web frontend or Perl libraries are missing'

# --- 8. Restore real systemctl for runtime ---
if [ -e /usr/bin/systemctl.distrib ]; then
    log "Restoring real systemctl..."
    rm -f /usr/bin/systemctl
    dpkg-divert --local --rename --remove /usr/bin/systemctl
fi

# Enable services so they start with systemd
systemctl enable apache2
systemctl enable loxberry
systemctl enable mosquitto

# --- Post-install: Apache + LoxBerry config ---
log "Configuring Apache for LoxBerry..."

# Environment
echo 'LBHOME=/opt/loxberry' >> /etc/environment
echo 'PERL5LIB=/opt/loxberry/libs/perllib' >> /etc/environment
echo 'export LBHOME=/opt/loxberry' >> /etc/apache2/envvars
echo 'export PERL5LIB=/opt/loxberry/libs/perllib' >> /etc/apache2/envvars

# Create config files
cp -f /opt/loxberry/config/system/general.json.default /opt/loxberry/config/system/general.json
htpasswd -bc /opt/loxberry/config/system/htusers.dat loxberry loxberry
chown -R loxberry:loxberry /opt/loxberry/config

# Apache vhost
cat > /etc/apache2/sites-available/loxberry.conf << 'VHOST'
<VirtualHost *:80>
    ServerName loxberry
    DocumentRoot /opt/loxberry/webfrontend/html

    SetEnv LBHOME /opt/loxberry
    SetEnv PERL5LIB /opt/loxberry/libs/perllib

    <Directory /opt/loxberry/webfrontend/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    Alias /admin /opt/loxberry/webfrontend/htmlauth
    Alias /htmlauth /opt/loxberry/webfrontend/htmlauth
    <Directory /opt/loxberry/webfrontend/htmlauth>
        Options Indexes FollowSymLinks ExecCGI
        AllowOverride All
        Require all granted
        AddHandler cgi-script .cgi .pl
        SetEnv PERL5LIB /opt/loxberry/libs/perllib
        SetEnv LBHOME /opt/loxberry
    </Directory>

    ScriptAlias /cgi-bin /opt/loxberry/webfrontend/cgi
    <Directory /opt/loxberry/webfrontend/cgi>
        Options ExecCGI
        AllowOverride All
        Require all granted
        SetEnv PERL5LIB /opt/loxberry/libs/perllib
        SetEnv LBHOME /opt/loxberry
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/loxberry_error.log
    CustomLog ${APACHE_LOG_DIR}/loxberry_access.log combined
</VirtualHost>
VHOST

# Apache modules and sites
a2dissite 000-default
a2ensite loxberry
a2enmod cgi rewrite

# Auto-start services
systemctl enable apache2
systemctl enable loxberry
systemctl enable mosquitto 2>/dev/null || true

# --- 9. Cleanup ---
log "Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* "$TMP"

log "LoxBerry bootstrap complete."
