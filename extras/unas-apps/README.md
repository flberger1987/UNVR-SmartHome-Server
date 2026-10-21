# Apps on a converted UNVR

UniFi Network Application (with MongoDB), LoxBerry, Dockge and optionally
UniFi Protect as containers on the converted UNAS, each service on its own LAN
address. Verified on 2026-10-21 on the four-bay UNVR from the main README.

| Service | Address | Notes |
| --- | --- | --- |
| UniFi Network 10.6.106 | `https://<UNIFI_IP>:8443` | MongoDB 4.4.18 shares its network namespace (127.0.0.1 only) |
| LoxBerry 3.0.1.3 | `http://<LOXBERRY_IP>/` | default login `loxberry`/`loxberry`, change it |
| Dockge | `http://<DOCKGE_IP>:5001` | manages the `unas-apps` and `protect` stacks |
| UniFi Protect (UNVR 5.1.33) | `https://<PROTECT_IP>/` | optional, see [UniFi Protect](#unifi-protect) |
| UniFi OS (Cloud Key Gen2 Plus 6.0.11) | `https://<UCKP_IP>/` | optional, Network + Protect in one UniFi OS, see [UniFi OS as a Cloud Key](#unifi-os-as-a-cloud-key-gen2-plus) |

LoxBerry also answers SSH on port 22 for the user `loxberry`, keys only: put
public keys into `/opt/loxberry/.ssh/authorized_keys` (in the `loxberry`
volume, survives image updates).

## Quick start (from the Mac)

```bash
extras/unas-apps/build-images.sh                    # arm64 images + static Docker/crun/compose
extras/unas-apps/install-on-unas.sh root@<UNAS-IP>  # Docker service on the pool, writes .env
# edit <pool>/.unas-apps/data/stacks/unas-apps/.env (LAN values), then:
extras/unas-apps/install-on-unas.sh root@<UNAS-IP> --images --up
```

Requirements: a storage pool created in UniFi Drive, SSH as root with a key,
`prebuilt/modules/4.19.152-alpine-unvr/extra/macvlan.ko` from Git LFS, about
8 GB free on the Mac for the image builds.

## Why it is built this way

The UNVR 5.1.33 kernel (4.19.152) is a trimmed vendor kernel. What it lacks and
what replaces it:

| Missing in the kernel | Consequence | Here |
| --- | --- | --- |
| `veth`, `bridge`, netfilter/iptables | no Docker bridge networks, no port publishing, no embedded DNS | `bridge: none`, `iptables: false`; services on **macvlan** (`macvlan.ko` built by `tools/build-modules.sh` into `prebuilt/.../extra/`); each container gets `./resolv.conf` with `LAN_DNS` |
| `CONFIG_BPF_SYSCALL`, `CONFIG_CGROUP_BPF` (host uses cgroup v2) | runc and crun cannot apply device rules; every container fails (`bpf_prog_query(BPF_CGROUP_DEVICE)`) | **crun with `--cgroup-manager=disabled`**: no per-container CPU/RAM limits or `docker stats`. Memory is capped inside the apps (`MEM_LIMIT`, `--wiredTigerCacheSizeGB`) |
| pids/cpuset controllers, seccomp | warnings only | none needed |

BPF support cannot be added as a module; it would need a custom kernel, which
the conversion guard pins and Ubiquiti's vendor drivers would be missing from.

Other details:

- Docker is the static 28.5.2 build (last line before the cgroup v1
  deprecation of v29), installed on the pool under `<pool>/.unas-apps/`, data
  root on the pool (Btrfs storage driver). Nothing goes through apt, which the
  conversion locks down.
- `unas-docker.service` waits for the UniFi Drive pool to be mounted, loads
  `macvlan.ko`, then starts dockerd on a private socket
  (`/run/unas-docker.sock`); `/usr/local/bin/docker` points there.
- LoxBerry runs systemd. Because crun gives it no cgroup of its own, the
  container gets the host cgroup tree (`cgroup: host`, `/sys/fs/cgroup` rw);
  the service has `Delegate=yes`, and the PID namespace keeps host processes
  out of reach of the container's systemd.
- LoxBerry is built from the Debian 12 installer pinned to LoxBerry 3.0.1.3
  (`loxberry/base`, adapted from
  [leberert/loxberry-docker-arm64](https://github.com/leberert/loxberry-docker-arm64),
  Apache-2.0). The upstream default installer now targets LoxBerry 4 on
  Debian 13.
- The UNAS itself cannot reach macvlan addresses (macvlan isolates its parent);
  every other device on the LAN can.
- The UniFi controller joins MongoDB's network namespace
  (`network_mode: service:unifi-db`), so the database, which rarely restarts,
  owns the LAN address. If Docker's restart policy restarts the owner on its
  own, the joined container keeps a dead namespace; `unas-netns-guard.timer`
  checks every minute and restarts such containers.

## Restoring a controller backup

A backup from a UniFi OS console (UDM, Cloud Gateway, Cloud Key Gen2+,
UniFi OS Server) restores sites and devices, but not the admins: those live in
UniFi OS, and the standalone server has no UI account sign-in. Afterwards no
login works. Create a local super admin (password typed in the terminal,
stored as SHA-512 crypt hash):

```bash
extras/unas-apps/unifi-add-admin.sh root@<UNAS-IP>
```

The same script resets the password of an existing admin.

## UniFi Protect

Protect runs from the box's own UNVR 5.1.33 userland (UniFi OS + Protect,
booted by systemd) in a container on its own address, next to UniFi Drive:

```bash
extras/unas-apps/protect/install-protect.sh root@<UNAS-IP> --ip <PROTECT_IP> --size 2T --up
```

Everything is built on the UNAS from `/boot/firmware/rootfs`; no firmware
passes through the Mac or Git. The script

- creates `<pool>/.unas-apps/protect` as a Btrfs subvolume without
  copy-on-write, so recordings are never part of a pool snapshot,
- puts a fixed-size ext4 image (`srv.img`, `--size`) into it, which
  `unas-docker` loop-mounts on `srv/` before Docker starts; Protect sees that
  size as its disk and runs its retention against it,
- writes an identity of its own (`system.info`, `board.info`: UNVR board data,
  serial and MACs derived from `--mac`, new UUID), so the container never
  presents the box's real serial,
- builds `unvr-protect:5.1.33` (`protect/Dockerfile`) and the `protect` stack.

Safety: the container is not privileged, has no device nodes and drops
`CAP_MKNOD`; the UNVR storage daemon, the post-reset disk wipe and all
hardware, LED, fan and network services are masked in the image. `ustorage`
is a stand-in that reports the fixed volume as one healthy disk.

Limits: UniFi OS inside stays at 5.1.33 (it is the image); app updates of
Protect from within its UniFi OS are untested. Storage pages in its UniFi OS
show the stand-in disk.

Notes from the first setup: UniFi OS moves Protect's Postgres cluster onto
`/srv` and recreates `/srv` while doing so (only the container's own volume).
If Protect then answers its API with HTTP 500, restart it once:
`docker exec unifi-protect systemctl restart unifi-protect`.

## UniFi OS as a Cloud Key Gen2 Plus

UniFi OS only installs the apps its model allows. On the UNVR that is Protect,
Access, InnerSpace and Connect; on the UNAS Pro identity of the host only
Drive. The Cloud Key Gen2 Plus (UCKP) allows Network **and** Protect (plus
Access, Talk, Connect, InnerSpace), and it suits this box: ARMv8.0 like the
AL-324, and its Network app needs no gateway hardware (unlike UDM, UDR or UCG).
Its own kernel is 3.18, so the Debian 13 userland runs fine on 4.19.

```bash
extras/unas-apps/uckp/install-uckp.sh root@<UNAS-IP> --ip <UCKP_IP> --size 200G --up
```

The UNAS downloads the UCKP firmware (6.0.11, pinned SHA-256) from Ubiquiti,
imports its rootfs (one squashfs inside the `.bin`) and builds `uckp-os:6.0.11`
(`uckp/Dockerfile`). Layout and safety are those of the Protect container: a
no-CoW subvolume `<pool>/.unas-apps/uckp` with `data/`, `persistent/` and a
fixed-size `srv.img` as the Cloud Key's HDD, an identity of its own (model ID
`0xe970`, serial and MACs from `--mac`), no device access, and all storage,
RAID, LCD, fan, Bluetooth, power and host-network services masked. The host's
`/proc/mtd` is hidden behind an empty table, otherwise the boot hook runner
tries to mount the UNVR's config flash; boot hooks that reorganise partitions
or `/srv` are removed.

Network 10.6.106 comes preinstalled (same version as the standalone server),
Protect is installed from UniFi OS. As real UniFi OS, it signs in with the UI
account and restores UniFi OS backups including their admins. The invented
serial is accepted by the UI cloud (tested with the Protect container).

RAM: the box has 4 GB. Running it next to the standalone controller and the
UNVR Protect container is fine for a test; for good it replaces both.

## Moving to another network

The stack directory keeps a second env file for the target network:

```bash
ssh root@<UNAS-IP>
cd /volume/<pool>/.unas-apps/data/stacks/unas-apps
cp .env.target .env        # or edit LAN_SUBNET, LAN_GATEWAY, LAN_DNS, *_IP
exit
extras/unas-apps/install-on-unas.sh root@<UNAS-IP> --up   # rewrites resolv.conf, recreates
```

In UniFi Network, set *Settings → System → Inform Host Override* to the new
controller address if devices do not find it by L2 discovery.

## Testing in a DHCP network

Docker cannot lease addresses for macvlan containers. For a temporary test,
lease addresses for the fixed MACs (`UNIFI_MAC`, `LOXBERRY_MAC`) with
`udhcpc` in a throwaway container on a macvlan network and use those addresses
in `.env` while the lease is valid.
