# UniFi Protect from the UNVR 5.1.33 firmware, as a container on the converted
# UNVR (UniFi OS + Protect, booted by systemd). Built on the UNAS itself:
#
#   mount -o loop,ro /boot/firmware/rootfs /mnt/x   # the box's own signed 5.1.33 rootfs
#   tar -C /mnt/x --numeric-owner -c . | docker import - unvr-rootfs:5.1.33
#   docker build --network none -t unvr-protect:5.1.33 .
#
# Safety first: the container runs unprivileged without device access, and every
# service that touches disks, RAID, LEDs, fans, SFP or the host network is masked
# here. The storage daemon (usd) and the post-reset disk wipe must never run.
FROM unvr-rootfs:5.1.33

RUN set -e; \
    cd /etc/systemd/system; \
    for unit in \
        uscsi-reset-wipe.service uscsi-disk-ready.service uscsi-rescan.service \
        usd.service usdbd.service ustated.service uhwd.service \
        rpsd.service sfpd.service lm-sensors.service uled-bootup-check.service \
        bluetooth-controller@hci0.service ble-http-transport.service \
        systemd-networkd.service systemd-networkd.socket networkd-dispatcher.service \
        systemd-networkd-fallbacker@enp0s1.service systemd-networkd-fallbacker@enp0s2.service \
        systemd-resolved.service gw-ip-monitor.service \
        systemd-udevd.service systemd-udev-trigger.service \
        systemd-udevd-control.socket systemd-udevd-kernel.socket \
        systemd-modules-load.service systemd-sysctl.service kmod-static-nodes.service \
        systemd-binfmt.service systemd-timesyncd.service \
        ucore-setup-listener.service ubnt-dpkg-restore.service earlyoom.service \
        rsync.service rpcbind.service rpcbind.socket nfs-client.target \
        ssh.service sysstat.service; \
    do ln -sf /dev/null "$unit"; done; \
    hooks=/usr/lib/ubnt/hooks/system/bootup-top; \
    rm -f "$hooks/01-bootup_top_wa.sh" "$hooks/10-srv-link" "$hooks/10-scan-dot-srv" \
          "$hooks/60-network-speed-init.sh"; \
    mv /sbin/ubnt-tools /sbin/ubnt-tools.real; \
    mv /usr/bin/ustorage /usr/bin/ustorage.real; \
    mkdir -p /srv /tmp /var/opt/unifi-protect/tmp

COPY ubnt-tools /sbin/ubnt-tools
COPY ustorage /usr/bin/ustorage

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
