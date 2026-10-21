# UniFi OS of a Cloud Key Gen2 Plus (UCKP 6.0.11: Network preinstalled,
# Protect, Access, Talk ... installable) as a container on the converted UNVR.
# The UCKP is ARMv8.0 like the UNVR's AL-324, and its Network app needs no
# gateway hardware. Built on the UNAS by install-uckp.sh from the firmware's
# rootfs (uckp-rootfs:6.0.11), never stored in Git.
#
# Same safety rules as the Protect container: unprivileged, no device access,
# and every service that touches disks, RAID, the LCD, fan, Bluetooth, power or
# the host network is masked. usd/ustated and the disk wipe must never run.
FROM uckp-rootfs:6.0.11

RUN set -e; \
    cd /etc/systemd/system; \
    for unit in \
        uscsi-reset-wipe.service uscsi-disk-ready.service uscsi-rescan.service \
        usd.service usdbd.service ustated.service uhwd.service ufcd.service \
        storage-target-mode.target unifi-sdcard@.service ustd-swap@.service ubnt-zram-swap.service \
        mdmonitor.service mdmonitor-oneshot.timer mdcheck_start.timer mdcheck_continue.timer \
        e2scrub_all.timer e2scrub_reap.service fstrim.timer \
        infctld.service infctld-emergency.service device-autofix.service \
        device-poweroff.service device-powerloss.service \
        ck-ui.service ck-splash-reboot.service ck-splash-shutdown.service ulcmd.service \
        uled-bootup-check.service ubnd.service sfpd.service rpsd.service \
        wcnss.service wcnss-bluetooth.service bluetooth.service ble-http-transport.service \
        serial-getty@ttyHSL0.service \
        systemd-networkd.service systemd-networkd.socket networkd-dispatcher.service \
        systemd-networkd-fallbacker@eth0.service fallbacker-trigger.service \
        systemd-network-generator.service systemd-resolved.service gw-ip-monitor.service \
        systemd-udevd.service systemd-udev-trigger.service \
        systemd-udevd-control.socket systemd-udevd-kernel.socket \
        systemd-modules-load.service systemd-sysctl.service kmod-static-nodes.service \
        systemd-binfmt.service proc-sys-fs-binfmt_misc.automount systemd-timesyncd.service \
        sys-kernel-debug.mount sys-kernel-tracing.mount sys-kernel-config.mount \
        sys-fs-fuse-connections.mount dev-hugepages.mount \
        ucore-setup-listener.service ubnt-dpkg-restore.service earlyoom.service \
        ssh.service ssh.socket sysstat.service apt-daily.timer apt-daily-upgrade.timer \
        systemd-firstboot.service; \
    do ln -sf /dev/null "$unit"; done; \
    # boot hooks that reorganise partitions or /srv (data partition backup, srv links)
    hooks=/usr/lib/ubnt/hooks/system/bootup-top; \
    rm -f "$hooks/01-bootup_top_wa.sh" "$hooks/10-srv-link" "$hooks/10-scan-dot-srv"; \
    mv /sbin/ubnt-tools /sbin/ubnt-tools.real; \
    mv /usr/bin/ustorage /usr/bin/ustorage.real; \
    mkdir -p /data /persistent /srv /var/opt/unifi-protect/tmp; \
    # unifi-core reads eth0's DNS from systemd-resolved, which is masked here
    printf '%s\n' 'd /run/systemd/resolve 0755 root root -' \
        'L+ /run/systemd/resolve/resolv.conf - - - - /etc/resolv.conf' \
        'L+ /run/systemd/resolve/stub-resolv.conf - - - - /etc/resolv.conf' \
        > /usr/lib/tmpfiles.d/unas-resolv.conf

COPY ubnt-tools /sbin/ubnt-tools
COPY ustorage /usr/bin/ustorage

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
