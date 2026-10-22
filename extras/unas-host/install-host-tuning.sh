#!/bin/bash
# Reduce writes to the boot medium (SD card) of a converted UNVR (run on the Mac).
#
#   extras/unas-host/install-host-tuning.sh root@<UNAS-IP>
#
# Measured before (24 h, 2026-10-21/22): ~2.0 GB/day on the SD card, of which
# /data 1.15 GB (UniFi Drive's Postgres and app logs; UniFi Drive's
# notificationManager alone logs ~80 MB/day of disk iostat events),
# /var/log 0.34 GB (syslog files) and the overlay root 0.3-0.47 GB
# (/var/tmp, Samba's socket directory). Logs are not needed across reboots,
# so they go to RAM; state (Postgres) stays on the card with fewer checkpoints.
#
# Installs (all under /etc, which lives on the persistent overlay):
#   journald: journal in RAM only (64 MB)
#   unas-volatile-logs.service: early at boot, before any service that logs,
#     /var/log and the app log directories on /data become small tmpfs mounts
#     (directory skeleton and owners kept); /etc/samba/private/msg.sock too
#   var-tmp.mount: /var/tmp as tmpfs
#   unas-log-trim.service: quiet loop, every 5 min deletes rotated logs and
#     truncates any log over 2 MB in those tmpfs mounts (logrotate.timer does
#     not run on this host), so RAM use stays at a few MB
#   tmpfs sizes are upper bounds (RAM is used only for content): /var/log and
#     UniFi Drive's logs 16 MB, other app logs 4 MB each, /var/tmp 32 MB
#   Postgres (host cluster 14-main): checkpoint every 30 min instead of 5,
#     WAL compression
# The RAM mounts take effect at the next reboot; the rest immediately.
set -Eeuo pipefail
target=${1:?usage: $0 root@<UNAS-IP>}
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

remote 'bash -s' <<'EOF'
set -euo pipefail

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/90-unas-volatile.conf <<'CONF'
# Journal in RAM only; logs are not needed across reboots (SD card wear).
[Journal]
Storage=volatile
RuntimeMaxUse=64M
CONF

cat > /usr/local/sbin/unas-volatile-logs <<'SH'
#!/bin/bash
# Early at boot: put log directories on small tmpfs mounts (SD card wear).
# Keeps the directory skeleton, owners and modes; existing log contents stay
# hidden underneath on the card.
set -u
ram() {   # ram <dir> <size>
    local d=$1 size=$2 mode owner skel
    [ -d "$d" ] || return 0
    [ "$(stat -f -c %T "$d")" = tmpfs ] && return 0
    mode=$(stat -c %a "$d"); owner=$(stat -c %u:%g "$d")
    skel=$(mktemp)
    # directories plus small files (wtmp, btmp, lastlog, ...) as a skeleton
    (cd "$d" && find . -xdev \( -type d -o \( -type f -size -64k \) \) -print0 \
        | tar --null --no-recursion -cf "$skel" -T - 2>/dev/null)
    mount -t tmpfs -o "size=$size,mode=$mode,nosuid,nodev,noatime" tmpfs "$d" || { rm -f "$skel"; return 1; }
    chown "$owner" "$d"
    tar -C "$d" -xpf "$skel" 2>/dev/null
    rm -f "$skel"
}
ram /var/log 16m
for d in /data/unifi-drive/logs; do ram "$d" 16m; done
for d in /data/ulp-go/log /data/unifi-core/logs /data/ucs-agent/log /data/uid/log \
         /data/ms/logs /data/ds/logs /data/unifi-directory/log /data/unifi-protect/logs \
         /data/ai-feature-console/logs; do
    ram "$d" 4m
done
# Samba creates and deletes a socket per process here
ram /etc/samba/private/msg.sock 1m
exit 0
SH
chmod 755 /usr/local/sbin/unas-volatile-logs

cat > /etc/systemd/system/unas-volatile-logs.service <<'UNIT'
[Unit]
Description=Log directories in RAM (SD card wear)
DefaultDependencies=no
After=local-fs.target
Before=sysinit.target syslog-ng.service
ConditionPathIsMountPoint=/data

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/unas-volatile-logs

[Install]
WantedBy=sysinit.target
UNIT

cat > /etc/systemd/system/var-tmp.mount <<'UNIT'
[Unit]
Description=/var/tmp in RAM (SD card wear)

[Mount]
What=tmpfs
Where=/var/tmp
Type=tmpfs
Options=mode=1777,size=32m,nosuid,nodev,noatime

[Install]
WantedBy=local-fs.target
UNIT

cat > /usr/local/sbin/unas-log-trim <<'SH'
#!/bin/bash
# Keep the RAM log mounts small: every 5 min delete rotated logs and truncate
# anything over 2 MB. Only touches directories that are tmpfs mounts.
dirs="/var/log /data/unifi-drive/logs /data/ulp-go/log /data/unifi-core/logs
      /data/ucs-agent/log /data/uid/log /data/ms/logs /data/ds/logs
      /data/unifi-directory/log /data/unifi-protect/logs /data/ai-feature-console/logs"
while :; do
    for d in $dirs; do
        [ -d "$d" ] && [ "$(stat -f -c %T "$d")" = tmpfs ] || continue
        find "$d" -xdev -type f \( -name '*.gz' -o -name '*.[0-9]' -o -name '*.[0-9].log' \
            -o -name '*.old' -o -name '*-20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*.log' \) -delete 2>/dev/null
        find "$d" -xdev -type f -size +2M -exec truncate -s 0 {} + 2>/dev/null
    done
    sleep 300
done
SH
chmod 755 /usr/local/sbin/unas-log-trim

cat > /etc/systemd/system/unas-log-trim.service <<'UNIT'
[Unit]
Description=Keep the RAM log mounts small
After=unas-volatile-logs.service

[Service]
ExecStart=/usr/local/sbin/unas-log-trim
Restart=always
RestartSec=60
Nice=19
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
UNIT

# Postgres of the host (UniFi Drive etc.): fewer checkpoints, compressed WAL.
# synchronous_commit is already off on UniFi OS (CLUSTER_ARGS).
if [ -d /etc/postgresql/14/main/conf.d ]; then
    cat > /etc/postgresql/14/main/conf.d/90-unas-sd.conf <<'CONF'
# SD card wear: checkpoint every 30 min instead of 5, compressed WAL
checkpoint_timeout = 30min
wal_compression = on
CONF
    chown postgres:postgres /etc/postgresql/14/main/conf.d/90-unas-sd.conf
    su postgres -s /bin/sh -c "psql -p 5432 -qtAc 'select pg_reload_conf()'" >/dev/null
    echo "postgres: checkpoint_timeout=$(su postgres -s /bin/sh -c "psql -p 5432 -tAc 'show checkpoint_timeout'"), wal_compression=$(su postgres -s /bin/sh -c "psql -p 5432 -tAc 'show wal_compression'")"
fi

systemctl daemon-reload
systemctl restart systemd-journald
systemctl enable unas-volatile-logs.service var-tmp.mount unas-log-trim.service >/dev/null 2>&1
systemctl restart unas-log-trim.service
echo "installed; RAM log mounts take effect at the next reboot"
EOF
