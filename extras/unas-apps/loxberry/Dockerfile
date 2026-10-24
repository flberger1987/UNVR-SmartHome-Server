# LoxBerry for a converted UNVR, on top of the base image in ./base (adapted
# from github.com/leberert/loxberry-docker-arm64, built as loxberry-arm64:base).
#
# With its own macvlan address LoxBerry keeps its normal ports. Only services
# that must not run inside a container are masked: clock sync belongs to the
# host, and the container is privileged with a writable /proc/sys and /sys, so
# systemd-sysctl, systemd-modules-load and systemd-udev-trigger would set the
# NAS kernel's values, load modules and replay udev events for every host
# device on each start. For host networking instead, build with
#   --build-arg LB_HTTP_PORT=8090 --build-arg LB_MASK_EXTRA="smbd nmbd ssh avahi-daemon"
# to stay clear of UniFi OS (80/443), UniFi Drive (SMB) and the host SSH.
FROM loxberry-arm64:base

ARG LB_HTTP_PORT=80
ARG LB_MASK_EXTRA=""

RUN set -eu; \
    if [ "${LB_HTTP_PORT}" != 80 ]; then \
        sed -ri "s/^Listen 80\$/Listen ${LB_HTTP_PORT}/; /^<IfModule (ssl_module|mod_gnutls.c)>/,/^<\/IfModule>/d" /etc/apache2/ports.conf; \
        sed -ri "s/<VirtualHost \*:80>/<VirtualHost *:${LB_HTTP_PORT}>/" /etc/apache2/sites-available/*.conf; \
        grep -q "Listen ${LB_HTTP_PORT}" /etc/apache2/ports.conf; \
    fi; \
    for unit in systemd-timesyncd ntp ntpsec chrony \
                systemd-sysctl systemd-modules-load systemd-udev-trigger ${LB_MASK_EXTRA}; do \
        systemctl mask "$unit" >/dev/null 2>&1 || true; \
    done; \
    # SSH for the loxberry user with keys only (the default password is public);
    # keys go to /opt/loxberry/.ssh/authorized_keys, which lives in the volume.
    mkdir -p /etc/ssh/sshd_config.d; \
    printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\nAllowUsers loxberry\n' \
        > /etc/ssh/sshd_config.d/10-key-only.conf; \
    systemctl enable ssh >/dev/null 2>&1 || true; \
    # LoxBerry's own jobs (log maintenance, plugin crons, update check) run from
    # cron; the installer runs with a stubbed systemctl and leaves it disabled.
    systemctl enable cron >/dev/null 2>&1

EXPOSE 80 443 1883
