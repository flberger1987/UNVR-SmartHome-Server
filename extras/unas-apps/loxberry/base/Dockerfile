# syntax=docker/dockerfile:1.6
# LoxBerry for ARM64 (Raspberry Pi 3/4/5, Zero 2)
# Builds the official LoxBerry on a Debian 12 (Bookworm) base
# by faking the DietPi environment that the upstream installer expects.

FROM debian:bookworm

LABEL org.opencontainers.image.title="LoxBerry ARM64" \
      org.opencontainers.image.description="LoxBerry running in Docker on ARM64" \
      org.opencontainers.image.source="https://github.com/leberert/loxberry-docker-arm64" \
      org.opencontainers.image.licenses="Apache-2.0"

ENV DEBIAN_FRONTEND=noninteractive \
    TERM=xterm \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    container=docker

# systemd needs a real init signal + cgroup mount at runtime
STOPSIGNAL SIGRTMIN+3
VOLUME ["/sys/fs/cgroup", "/tmp", "/run", "/run/lock"]

# --- Base packages (single layer, cleaned in place) ---
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        systemd systemd-sysv dbus \
        wget curl jq git \
        ca-certificates gnupg \
        lsb-release \
        sudo procps \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
 # Strip systemd units that don't make sense in a container
 && find /etc/systemd/system /lib/systemd/system \
        -path '*.wants/*' \
        \( -name '*udev*' -o -name '*getty*' -o -name '*systemd-timesyncd*' \) \
        -exec rm -f {} + || true

# --- Run the LoxBerry installer (cached unless install.sh changes) ---
COPY lb-bootstrap.sh /usr/local/sbin/lb-bootstrap.sh
RUN chmod +x /usr/local/sbin/lb-bootstrap.sh \
 && /usr/local/sbin/lb-bootstrap.sh \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# LoxBerry web UI / SSH / Samba
EXPOSE 80 443 22 8080 8443

# Boot into systemd so LoxBerry services come up
CMD ["/lib/systemd/systemd"]
