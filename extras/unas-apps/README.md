# Apps on a converted UNVR

UniFi Network Application (with MongoDB), LoxBerry and Dockge as containers on
the converted UNAS, each service on its own LAN address. Verified on
2026-10-21 on the four-bay UNVR from the main README.

| Service | Address | Notes |
| --- | --- | --- |
| UniFi Network 10.6.106 | `https://<UNIFI_IP>:8443` | MongoDB 4.4.18 shares its network namespace (127.0.0.1 only) |
| LoxBerry 3.0.1.3 | `http://<LOXBERRY_IP>/` | default login `loxberry`/`loxberry`, change it |
| Dockge | `http://<UNAS-IP>:5001` | manages the `unas-apps` stack |

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
