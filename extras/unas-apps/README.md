# Apps on a converted UNVR

UniFi Network Application (with MongoDB), LoxBerry, Dockge and optionally
UniFi Protect as containers on the converted UNAS, each service on its own LAN
address. Verified on 2026-10-21 on the four-bay UNVR from the main README.

| Service | Address | Notes |
| --- | --- | --- |
| UniFi Network 10.6.106 (standalone) | `https://<UNIFI_IP>:8443` | optional (`--profile standalone-controller`), MongoDB 4.4.18 shares its network namespace; replaced by the Cloud Key UniFi OS below |
| LoxBerry 4 | `http://<LOXBERRY_IP>/` | built as 3.0.1.3, updated in place; default login `loxberry`/`loxberry`, change it (`loxberry/set-passwords.sh`) |
| Dockge | `http://<DOCKGE_IP>:5001` | manages the `unas-apps` and `protect` stacks |
| UniFi Protect (UNVR 5.1.33) | `https://<PROTECT_IP>/` | optional, see [UniFi Protect](#unifi-protect) |
| UniFi OS (Cloud Key Gen2 Plus 6.0.11) | `https://<UCKP_IP>/` | optional, Network + Protect in one UniFi OS, see [UniFi OS as a Cloud Key](#unifi-os-as-a-cloud-key-gen2-plus) |
| MJPEG camera for Protect (go2rtc 1.9.14) | `rtsp://<CAM_IP>:8554/<stream>`, ONVIF on port 1984 | optional, e.g. a Loxone Intercom as a Protect camera, see [MJPEG camera in UniFi Protect](#mjpeg-camera-in-unifi-protect) |
| Home Assistant 2026.10 (Container) | `http://<HA_IP>:8123` | optional, see [Home Assistant](#home-assistant) |

LoxBerry also answers SSH on port 22 for the user `loxberry`, keys only: put
public keys into `/opt/loxberry/.ssh/authorized_keys` (in the `loxberry`
volume, survives image updates).

LoxBerry's MQTT gateway reconnects to the broker by itself after a dropped
connection, but without its subscriptions: from then on it only publishes and
relays nothing to the Miniserver, not even its keepalive (seen 2026-10-25 when
the NAS swapped hard). A guard on the host restarts it then:

```bash
extras/unas-apps/loxberry/install-mqtt-guard.sh root@<UNAS-IP> [--remove]
```

`loxberry-mqtt-guard.timer` looks every minute at the gateway's connection to
the broker: the same process on a new connection, or 3 minutes without a
connection or without the process, restarts the gateway (only the gateway,
not the broker; at most once in 10 minutes) and reports it through the
monitor's Telegram bot. Tested by freezing the gateway for 100 s: the broker
dropped it after 48 s, it reconnected without subscriptions, the guard
restarted it 52 s later and the keepalive reached the Miniserver again,
2½ minutes in all (Loxone reports a fault after about 7). `loxberry-mqtt-guard
--status` shows the gateway and its connection.

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
  Debian 13. LoxBerry's own updater brings the build to 4.x and stays on
  Debian 12: `loxberry/update-loxberry.sh root@<UNAS> 4`.
- Updates and plugins install packages into the container layer, not the
  `/opt/loxberry` volume, so the stack runs `loxberry-unas:live`, the committed
  container (like UniFi OS); the backup, `install-on-unas.sh --up` and the
  update script commit it.
- The UNAS itself cannot reach macvlan addresses (macvlan isolates its parent);
  every other device on the LAN can.
- The UniFi controller joins MongoDB's network namespace
  (`network_mode: service:unifi-db`), so the database, which rarely restarts,
  owns the LAN address. If Docker's restart policy restarts the owner on its
  own, the joined container keeps a dead namespace; `unas-netns-guard`
  (a quiet loop service) checks every minute and restarts such containers.

## Backup and recovery

The complete rebuild, every recovery scenario and all pitfalls are in
[docs/RECOVERY.md](../../docs/RECOVERY.md). In short:

```bash
extras/unas-apps/backup-unas.sh root@<UNAS-IP>    # recovery set on the pool
extras/unas-apps/restore-unas.sh root@<UNAS-IP>   # load it back (after install-on-unas.sh)
extras/unas-apps/loxberry/restore-drill.sh root@<UNAS-IP>   # test LoxBerry from the set beside the live one
```

The recovery set holds the finished images (the UniFi OS containers as
`uckp-os:live`, with the apps installed inside them), the stack configuration
with the console identities, LoxBerry's volume and the newest Network, Protect,
UniFi OS console and Home Assistant backups.

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
UNVR Protect container is fine for a test; for good it replaces both. To move
from the standalone server: back it up, stop it (the services sit in the
`standalone-controller` profile, so the stack no longer starts them), set
`UCKP_IP` in the uckp stack's `.env` to the old controller address and
recreate; adopted devices keep informing that address. Then restore the
backup in the new Network app.

Under heavy disk load (RAID resync, swapping) the Network app may start for
longer than its 15-minute systemd timeout; the image raises it to 45 minutes.
A restore can fail the same way: after the import the app drops its old
database, MongoDB 3.6 flushes everything to disk first and blocks meanwhile,
and on RAID 6 HDDs with btrfs that took over three minutes, longer than the
app's MongoDB timeout ("After-import cleanup failed", "Failed to restore
backup"). What made it work (2026-10-22):

1. stop the old controller (memory, swap and disk load),
2. pause a running RAID resync: `echo frozen > /sys/block/md3/md/sync_action`
   (resume afterwards with `echo idle > ...`; it continues where it stopped),
3. raise the app's MongoDB timeout for the restore: `db.mongo.timeout=900` in
   `/data/unifi/data/system.properties` inside the container, then
   `systemctl restart unifi`. The unit is not milliseconds: 900000 overflows
   and the app crash-loops at startup ("timeout converted to milliseconds must
   not be greater than Integer.MAX_VALUE"). Remove the line afterwards.

The backup is first imported into `ace_restore`; if a restore fails, the
running app keeps an empty `ace`, nothing else is touched.

## Home Assistant

`homeassistant/compose.yaml`: Home Assistant as a plain container (the
"Container" install type) on its own LAN address. Home Assistant OS and
"Supervised" need the Supervisor, which requires cgroup and AppArmor features
this kernel lacks; so there is no add-on store and no update button. What an
add-on would be runs as a container of its own (an MQTT broker already runs in
LoxBerry; ESPHome, Zigbee2MQTT, Node-RED as stacks in Dockge), and an update
is a new image tag in the compose file. Integrations and HACS work as usual.
There is no free USB port (the SD card reader takes it) and no Bluetooth: use
network devices (a LAN/PoE Zigbee coordinator, ESPHome Bluetooth proxies).

Config and the recorder database live on the RAID
(`<pool>/.unas-apps/data/homeassistant/config`); the recovery set keeps the
config without databases and logs, and the two newest of Home Assistant's own
backups (config and database). Turn those on in Settings → System → Backups →
"Set up backups": daily (here 04:45, before the weekly set on Saturday 23:00
and the nightly cloud sync), local, keep 7. Home Assistant encrypts them; keep
the emergency kit it offers there (the key), a restore asks for it. A backup
of this setup is about 80 MB. Restoring one: a fresh Home Assistant offers
"Restore from backup" in its onboarding (upload the `.tar`), a running one in
Settings → System → Backups.

[`homeassistant/design/`](homeassistant/design/README.md): card styles for
YAML dashboards in the look of Apple Home (uix).

Add to `configuration.yaml`, to keep the database small:

```yaml
recorder:
  purge_keep_days: 10
  commit_interval: 30
  exclude:
    event_types:
      - loxone_event   # PyLoxone (Loxone via HACS) fires it with > 32 kB
```

MQTT: an extra broker user on LoxBerry with `loxberry/mqtt-user.sh` (see the
[LoxBerry pitfalls](../../docs/RECOVERY.md#loxberry) in RECOVERY.md); Home Assistant reaches the broker on
LoxBerry's address, port 1883.

Memory: about 300 MB in the base setup (measured 2026-10-25); with UniFi OS
(Network + Protect) and LoxBerry on the 4 GB box about 0.8 GB stays available.
That is not much: some custom integrations need a lot more (a robot vacuum
integration that renders its map at full resolution grew to 2.2 GB in 20
minutes) or grow over hours. Docker can't cap a container here (no cgroups),
so a growing Home Assistant fills the swap and then starves UniFi OS and
Protect. The guard restarts it above a limit and reports it via the monitor's
Telegram bot:

```bash
extras/unas-apps/homeassistant/install-mem-guard.sh root@<UNAS-IP> [--limit 1200] [--warn 900] [--no-mqtt]
```

`ha-mem-guard.timer` checks RAM + swap of the Home Assistant process every 2
minutes: above `--warn` (MB) one Telegram message (and one when it is back),
above `--limit` in 2 runs in a row `docker restart homeassistant`. It also
publishes the values through LoxBerry's MQTT gateway (UDP into the
`loxberry` container, no broker login) with MQTT discovery, so Home Assistant
gets a device "UNAS Pro" with its own RAM, swap and total plus the NAS's
available memory and swap use, with history: a slow leak shows up as a rising
line long before the limit. `ha-mem-guard --status` shows the current use;
`--remove` uninstalls it.

## MJPEG camera in UniFi Protect

Protect records H.264 from cameras it can adopt; since 5.0 that includes
third-party cameras speaking ONVIF. A camera or door station that only sends
MJPEG (e.g. the Loxone Intercom, `/mjpg/video.mjpg`) gets there through
[go2rtc](https://github.com/AlexxIT/go2rtc): a container on its own LAN
address encodes the MJPEG to H.264 and offers it over RTSP plus an ONVIF
server. Protect needs one address per camera, hence one stack per camera.
Other clients (e.g. the Loxone app) keep reading the camera directly.

```bash
extras/unas-apps/mjpeg-camera/install-mjpeg-camera.sh root@<UNAS-IP> --ip <CAM_IP> \
    --url http://<camera>/mjpg/video.mjpg --name door-cam --keep-every 4 --fps 5 --up
```

The script asks for the camera login (Basic auth) in the terminal, writes the
stack to `<pool>/.unas-apps/data/stacks/<name>/` (shows up in Dockge, in the
recovery set and in the health monitor) with a root-only `.env` and a random
RTSP password, and prints how to copy that password to the clipboard.

Adopting it: Protect → Settings → System → "Discover third-party cameras"
on; then Devices → the (?) next to the search → "Try advanced adoption":
camera IP, user and password from `.env`. The dialog has no port field;
Protect finds go2rtc's ONVIF service on port 1984 and keeps that port, so the
stack stays on 1984. Recording mode as for any camera ("Always").

How the encoding is kept cheap on the Cortex-A57 (measured with a
1280×720 camera sending ~19 fps, no hardware video encoder in the AL-324):

| Choice | CPU of the UNAS | Why |
| --- | --- | --- |
| ffmpeg reads the camera itself | — | go2rtc's own MJPEG reader handing ~25 Mbit/s on to ffmpeg over internal RTSP cost ~35 % |
| keep every Nth frame, drop the rest **before decoding** (`noise` bitstream filter) | 4 % for 5 fps | decoding all and thinning afterwards: 8.5 %; encoding all 19 fps: 14 % |
| x264 `ultrafast` with CABAC and 8×8 transform on, 1 thread, full-range YUV kept | 35 ms per frame | go2rtc's default (`superfast`): 58 ms; plain `ultrafast` is Baseline, which Protect does not record reliably |
| `-r` on the output | — | without it ffmpeg assumes 25 fps for MJPEG and fills the stream up with copies |
| CRF with a bit rate cap | ~0.5 Mbit/s for a still scene | instead of the full cap all the time |

go2rtc reports a fixed 1920×1080, 30 fps, 8 Mbit/s over ONVIF, and Protect
keeps what it read at adoption. `patch-onvif-values.sh` (run by the
installer) writes a copy of the image's binary with the camera's values
(`--size`, `--fps`, `--kbps`) as text of the same length, which the stack
mounts over the original; run it again after changing the image version. A
camera adopted before has its values in the Protect database (`cameras.channels`,
with Protect stopped, see [RECOVERY.md](../../docs/RECOVERY.md#mjpeg-camera-in-protect)).

On the LAN the container answers only ONVIF and `/api/frame.jpeg` (snapshots,
no password, as Protect fetches them) on port 1984, and RTSP with the password
on 8554; go2rtc's web UI and stream editing are not reachable. The camera
sends its full MJPEG (~20–25 Mbit/s at 1280×720) to the container whatever
is kept; a camera on a 100 Mbit/s port then has room for about three more
viewers.

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
