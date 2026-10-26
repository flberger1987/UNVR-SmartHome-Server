# Rebuilding the converted UNVR from scratch

This is the runbook for the complete system built on a four-bay UNVR: the
converted host (UNAS Pro identity, UniFi Drive), Docker on the storage pool,
and the apps — UniFi OS from the Cloud Key Gen2 Plus firmware (Network and
Protect), LoxBerry and Dockge. It covers backups, every recovery scenario, the
complete build from zero, and every pitfall met on the way with its solution.

Site-specific values (addresses, MACs, serials, pool path) are not in this
public repository. They are in the private system sheet `SYSTEM.md` next to the
recovery set on the NAS (see [Private system sheet](#private-system-sheet)).

## The system

```
UNVR (4 bays, Annapurna AL-324, 4 GB RAM, boot medium: 32 GB SD card on USB)
├─ host: UniFi OS 5.1.33, UNAS Pro identity, UniFi Drive 4.3.10 (convert.sh)
│  ├─ RAID 6 pool (md3) → LVM → Btrfs:  /volume/<pool-uuid>
│  └─ /volume/<pool-uuid>/.unas-apps    everything below lives here
│     ├─ docker/          static Docker 28.5.2, crun, compose; data-root
│     ├─ data/stacks/     unas-apps (LoxBerry; optional standalone controller),
│     │                   uckp (UniFi OS), protect (optional UNVR Protect),
│     │                   one per MJPEG camera (optional, go2rtc),
│     │                   homeassistant (optional)
│     ├─ dockge/          Dockge's own stack
│     ├─ uckp/            Btrfs subvolume, no CoW, not in snapshots:
│     │                   data/ persistent/ srv.img (ext4, the "HDD") identity
│     └─ backup/          recovery set, SD card image, SYSTEM.md
└─ macvlan network unas-lan on the LAN port, one LAN address per app:
   UniFi OS (Cloud Key Gen2 Plus 6.0.11: Network 10.6.106, Protect 7.x)
   LoxBerry 4 · Dockge · [standalone UniFi Network Server] · [UNVR Protect]
   · [MJPEG camera for Protect] · [Home Assistant]
```

| Component | Built by | Documentation |
| --- | --- | --- |
| Conversion UNVR → UNAS Pro | `tools/run-conversion.sh` | [README](../README.md#runbook) |
| SD card wear reduction | `extras/unas-host/install-host-tuning.sh` | [below](#4-host-tuning) |
| Cooler fan set points (optional) | `extras/unas-host/install-fan-setpoints.sh` | [below](#4-host-tuning) |
| Docker, macvlan, app stack | `extras/unas-apps/install-on-unas.sh` | [extras/unas-apps/README.md](../extras/unas-apps/README.md) |
| UniFi OS (Network + Protect) | `extras/unas-apps/uckp/install-uckp.sh` | [README section](../extras/unas-apps/README.md#unifi-os-as-a-cloud-key-gen2-plus) |
| MJPEG camera in Protect (optional) | `extras/unas-apps/mjpeg-camera/install-mjpeg-camera.sh` | [README section](../extras/unas-apps/README.md#mjpeg-camera-in-unifi-protect) |
| Home Assistant (optional) | `extras/unas-apps/homeassistant/compose.yaml` | [README section](../extras/unas-apps/README.md#home-assistant) |
| Recovery set | `extras/unas-apps/backup-unas.sh`, `restore-unas.sh` | [below](#backups) |
| Health monitor, Telegram alerts | `extras/unas-host/install-monitor.sh` | [below](#11-monitoring-telegram) |

## What is stored where

| Place | Content | Survives |
| --- | --- | --- |
| SD card `boot1/2` | kernel, signed rootfs (UNVR 5.1.33) | — |
| SD card `boot3` = `/data` | host UniFi OS state: UniFi Drive (Postgres), users, shares, settings | reboots |
| SD card `boot4` = `/var/log` | host logs — **replaced by a RAM mount at boot** (host tuning) | — |
| SD card `boot5` = overlay | host `/etc`, `/usr/local`, `/root` changes (units, scripts, SSH keys, the monitor's Telegram token) | reboots |
| RAID pool | shares, `.unas-apps` (Docker, images, all app data, backups) | SD card loss |
| RAM | journal, logs, `/var/tmp`, container tmpfs | nothing |
| Ubiquiti cloud | UniFi OS console backups (Remote Access on), UI account | everything local |
| this repository | all tooling, prebuilt modules and Debian cache (Git LFS) | everything local |

## Backups

| What | How | Where | When |
| --- | --- | --- | --- |
| Recovery set: finished images (UniFi OS with its installed apps), stack config, console identities, LoxBerry data, newest Network, Protect, console and Home Assistant backups | `extras/unas-apps/backup-unas.sh root@<UNAS> --share <Drive share> --weekly` installs `unas-backup` and a weekly timer (Saturday 23:00, finished before the nightly cloud backup at 02:00; finished files are handed to UniFi Drive at once, `.part` files stay root-only); `unas-backup` on the NAS runs it by hand | `<share>/UNAS-Recovery/recovery/` (linked from `.unas-apps/backup/recovery`) | weekly, and after app installs/updates |
| Off-box copy | a UniFi Drive remote backup of that share (here: the nightly OneDrive task at 02:00), unencrypted | cloud | nightly |
| UniFi Network | autobackup in the Network app (set: daily 03:00, keep 7) | inside UniFi OS, newest two in the recovery set | daily |
| UniFi Protect (settings, users, device certificate; no video) | Protect itself, after settings changes | `/srv/unifi-protect/backups/*.zip` inside UniFi OS, newest two in the recovery set (`protect/`) | on change |
| UniFi OS console (console settings, users, Network, Protect) | Control Plane → Backups → Automatic Backups (set: weekly, Friday 04:00, keep 10), or "Backup Now" | local `/data/unifi-core/local-backups/<time>/*.unifi`, newest two in the recovery set (`unifi-os/`, with `.metadata.json`); uploaded to the Ubiquiti cloud (Remote Access on) | weekly |
| Home Assistant (config and database) | Settings → System → Backups (set: daily 04:45, local, keep 7; encrypted, key in the emergency kit) | `config/backups/*.tar` on the pool, newest two in the recovery set (`homeassistant/`) | daily |
| Not in any backup | Protect's video, events and its Postgres database on `srv.img` (Protect's backup holds its settings only) | — | — |
| SD card image | `backup-unas.sh … --sd-nightly` installs `unas-sd-image.timer`: every night at 00:30 a new image when the host changed since the last one (units, scripts, settings, firmware; not logs or the `/data` databases), at the latest every `SD_MAX_AGE_DAYS` (7, in `/etc/unas-backup.conf`). Each image is unpacked into the pool and every partition checked (journal replay, `e2fsck`) before it replaces the previous one; a failed check keeps the old image and leaves the unit failed, which the monitor reports. By hand: `unas-backup --sd-only` | `<share>/UNAS-Recovery/sd-card/sd-boot.img.zst` (+ `.sha256`, `.sfdisk`, `.date`, `.state`) | nightly check |
| Host settings | the install scripts in this repository (and `host-files.tar.zst` in the set without the monitor's Telegram token; the SD card image holds the whole card, token included) | Git | — |

Check a set without changing anything (checksums, every archive
decompresses, the Protect zips are readable, which apps each console backup
holds): `extras/unas-apps/restore-unas.sh root@<UNAS> --check`. `MANIFEST.txt`
lists the app backups; `unas-backup` warns when the newest console backup is
missing an app.

The app backups are restored in UniFi OS, not by `restore-unas.sh`:

| File in the set | Restores | Where |
| --- | --- | --- |
| `unifi-os/unifi_os_backup_*.unifi` | the whole console: settings, users, Network, Protect (the apps marked `ok` in its `.metadata.json`) | setup wizard of a new console: "Restore from Backup" → the cloud list or upload the file; on a running console Control Plane → Backups → "Restore from Backup File". Encrypted; only for a console of the same owner (UI account) |
| `protect/unifi_protect_backup.*.zip` | Protect's settings, users, device certificate (cameras adopted at the time re-adopt) | Control Plane → Backups → "Restore from Backup File", upload the zip; keep the file name, UniFi OS tells the type from it |
| `network/*.unf` | Network: sites, devices, settings | Network app → Settings → System → Backups ([restore under load](#restore-under-load)) |
| `homeassistant/*.tar` | Home Assistant: config, database, integrations | onboarding of a fresh Home Assistant: "Restore from backup", upload the file, enter the key from the emergency kit; on a running one Settings → System → Backups |

The recovery set is on the same disks as the apps. It covers a lost, reset or
replaced boot medium; the loss of the RAID needs the off-box copy (or the
cloud backup plus a rebuild from sources). Stable file names let the cloud
copy replace files instead of collecting old versions. The set is stored
unencrypted (decided for this installation): the Network backups in it hold
Wi-Fi passwords and device credentials, the Protect backups the private key
cameras trust, so the cloud account must be protected accordingly.

Restore drill (LoxBerry), with the live container untouched:

```bash
extras/unas-apps/loxberry/restore-drill.sh root@<UNAS-IP>   # [--keep | --cleanup]
```

It unpacks `loxberry-volume.tar.zst` into a scratch directory on the pool,
loads `images/loxberry-unas_live.tar.zst` under another tag (`RepoTags` in the
tar's `manifest.json`, `index.json` and `repositories` rewritten in the stream:
a plain `docker load` re-tags `loxberry-unas:live`, which the stack runs) and
starts a container with the options of the loxberry service in
`docker-compose.yml`, but another name, `--network none` and the scratch
directory as `/opt/loxberry`. It reports systemd's state, failed units,
services missing compared with the live container, Apache, every plugin with
its programs, web pages and settings, the MQTT gateway's settings and the
config files changed since the backup, then removes container, tag and
directory. Runs on 2026-10-24 with that night's set: volume 86 MB, image
loaded in 1½–2 minutes with exactly the saved image ID, systemd `running`
after 30–100 s without failed units, LoxBerry 4.0.0.15 with all five plugins,
under 100 MB of memory; only the Dreame gateway waited to restart (it needs
the Dreame cloud). Repeat it after larger LoxBerry changes.

## Recovery scenarios

| Situation | Path |
| --- | --- |
| SD card dead or the host reset to defaults, RAID intact | [A](#a-boot-medium-lost-pool-intact) |
| Everything lost (new disks, new pool) | [B](#b-everything-lost) with the off-box recovery set, otherwise [from zero](#from-zero-step-by-step) |
| One app broken | [C](#c-one-app-broken) |
| Controller configuration broken | [D](#d-controller-configuration-broken) |

### A. Boot medium lost, pool intact

The pool still holds Docker, every image, container and app data.

1. Preferred: write the last `sd-boot.img.zst` (its date in `sd-boot.date`)
   to a card of at least the same size (31.3 GB here) on another machine,
   `zstd -dc sd-boot.img.zst | sudo dd of=/dev/<card> bs=4M`, and boot.
   The host comes back exactly as it was imaged (host tuning, SSH keys, Drive
   state of that day); nothing else is needed. *(Not tested on this unit.)*
2. Without an image: the UNVR has to get its stock firmware back on a new
   card through Ubiquiti's recovery procedure (the recovery kernel lives on the
   SPI flash, not on the card), then [steps 1–4](#from-zero-step-by-step) with
   the drives **removed** during the conversion. *(Not tested on this unit.)*
3. Insert the drives. **Careful:** whether UniFi Drive adopts an existing pool
   after a new conversion is untested. If it only offers to create a new pool,
   stop — creating one erases the disks. The pool can be assembled by hand
   (`mdadm --assemble --scan`, `vgchange -ay`, mount the Btrfs volume) to
   rescue `.unas-apps/backup/`; then continue with scenario B.
4. `extras/unas-apps/install-on-unas.sh root@<UNAS>` — reinstalls the Docker
   service and units pointing at the existing data on the pool.
   Then `--up` (or just reboot): all containers come back with their data.
5. Rebuilt without an image (path 2): `extras/unas-host/install-monitor.sh root@<UNAS> --telegram --test`
   — the Telegram token is in no backup, enter it again ([step 11](#11-monitoring-telegram)).

### B. Everything lost

1. [Steps 1–6](#from-zero-step-by-step): converted host, new pool, host tuning,
   Docker.
2. Copy the off-box recovery set to `<pool>/.unas-apps/backup/recovery/`.
3. `extras/unas-apps/restore-unas.sh root@<UNAS>` — verifies the checksums,
   restores stack config and console identities, loads all images (the UniFi
   OS image `uckp-os:live` with its installed apps, `loxberry-unas:live` with
   LoxBerry's update and plugin packages), restores LoxBerry's volume.
4. `extras/unas-apps/uckp/install-uckp.sh root@<UNAS> --ip <UCKP_IP> --mac <UCKP_MAC> --size <SIZE>`
   — keeps the restored identity and image, creates the fixed-size volume.
5. `extras/unas-apps/install-on-unas.sh root@<UNAS> --up`
6. UniFi OS data was lost with the pool: on first start it is a new console
   with the old identity. Restore a console backup in the setup wizard
   ("Restore from Backup": from the cloud, or upload `unifi-os/*.unifi` from
   the set — one whose `.metadata.json` shows Protect `ok`), or set it up and
   restore the newest Network `.unf` and Protect `.zip` from the set
   ([app backups](#backups), [step 8](#8-unifi-os-cloud-key-gen2-plus)).
7. Monitoring: [step 11](#11-monitoring-telegram).

### C. One app broken

- Container misbehaves: `cd <pool>/.unas-apps/data/stacks/<stack> && docker compose up -d --force-recreate`
  (data stays on the volumes; for UniFi OS and LoxBerry the `:live` image
  must contain the installed apps and packages — see the live image pitfalls).
- Image broken: load it from the recovery set
  (`zstd -dc images/<name>.tar.zst | docker load`), or rebuild it
  (`install-uckp.sh … --rebuild`, `build-images.sh` for LoxBerry).

### D. Controller configuration broken

Restore a Network backup (`.unf`) in the Network app (Settings → System →
Backups). Under load follow [restore under load](#restore-under-load).
Protect: upload a `protect/*.zip` from the set (or one of Protect's own) in
Control Plane → Backups → "Restore from Backup File"; the whole console the
same way with a `.unifi` (see [app backups](#backups)).

## From zero, step by step

### 0. Prerequisites (Mac)

- macOS tools as in the [README](../README.md#install-the-macos-prerequisites),
  `git lfs install`, this repository cloned (LFS files present: `.ko` modules,
  Debian cache).
- Docker Desktop for `build-images.sh` (LoxBerry, image downloads).
- **Free disk space:** ≥ 6 GB for the conversion payload, ≥ 8 GB for the image
  builds. A full disk crashed Docker Desktop during this build; check first.
- An SSH key for the NAS (here: 1Password SSH agent; only the public key is
  ever copied).

### 1. Firmware baseline

UniFi OS **5.1.33** on the UNVR. From 6.x: `tools/downgrade-to-5.1.33.sh`
(see README runbook step 2: auto-updates off first).

### 2. Conversion

**Remove all drives.** Then `tools/run-conversion.sh --ip <UNVR-IP> --skip-controller-cleanup`
(about 25 minutes). Sign in with the account that **owns** the console; the
newest MFA code each time. Finish the UNAS Pro setup when asked.

### 3. Pool and SSH

1. *Control Plane → Console → SSH*: on, add the public key.
2. Insert the drives, create the pool in UniFi Drive (here RAID 6).
   The initial resync of 4 × 4 TB runs for days at the minimum speed while
   anything else uses the disks; the swap mirror `md0` is rebuilt only after
   it (both shown in `/proc/mdstat`).

### 4. Host tuning

`extras/unas-host/install-host-tuning.sh root@<UNAS>`, then reboot.
Journal in RAM, logs on small RAM mounts, Postgres with fewer checkpoints
(measured: ~2 GB/day on the SD card before; see pitfalls).

Optional, cooler fan set points: `extras/unas-host/install-fan-setpoints.sh root@<UNAS> --cpu 75 --hdd 44`
(`--reset` for Ubiquiti's defaults). It writes `/etc/ustd/fan.conf` and
`unas-fan-config.service`, which puts the file into ustd's status database
whenever `usdbd` starts; takes effect at once, no reboot.

### 5. SD card image

As in [Backups](#backups); keep it on the pool and off-box.

### 6. Docker and the stack

1. Mac: `extras/unas-apps/build-images.sh` (static Docker/crun/compose,
   LoxBerry image) — or skip the images when restoring from a recovery set.
2. `extras/unas-apps/install-on-unas.sh root@<UNAS>` (installs Docker on the
   pool, writes `.env`), edit `<pool>/.unas-apps/data/stacks/unas-apps/.env`
   (LAN subnet, gateway, DNS, addresses), then
   `install-on-unas.sh root@<UNAS> --images --up`.
3. Restoring instead: `restore-unas.sh root@<UNAS>` (scenario B).

### 7. LoxBerry and Dockge

- LoxBerry at `http://<LOXBERRY_IP>/`: set the admin password and SecurePIN
  with `extras/unas-apps/loxberry/set-passwords.sh root@<UNAS>` (typed in the
  terminal; web interface, system user, Samba). SSH: user `loxberry`, keys
  only; put public keys into `/opt/loxberry/.ssh/authorized_keys` (in the volume).
- A fresh build is LoxBerry 3.0.1.3; bring it to the current release with
  `extras/unas-apps/loxberry/update-loxberry.sh root@<UNAS> 4` (LoxBerry's own
  updater; rollback point first, commits `loxberry-unas:live`, restarts).
  A restored recovery set already has the updated `:live` image.
- Plugins: `loxberry/install-plugin.sh root@<UNAS> <zip-url|plugin.zip>` (a local
  zip is streamed over SSH into the container; `--dry-run` checks the zip without
  SecurePIN or install); Shelly via MQTT: `loxberry/shelly-mqtt.sh`.
- Dockge at `http://<DOCKGE_IP>:5001` manages all stacks.

### 8. UniFi OS (Cloud Key Gen2 Plus)

1. `extras/unas-apps/uckp/install-uckp.sh root@<UNAS> --ip <UCKP_IP> --mac <UCKP_MAC> --size 200G --up`
   — the UNAS downloads the UCKP firmware (pinned SHA-256), imports the rootfs,
   builds `uckp-os:6.0.11`, creates the no-CoW subvolume, the fixed-size
   volume and the identity. First start: 15–30 minutes.
2. `https://<UCKP_IP>/`: setup with the UI account. The storage step shows
   0 B and "requires 2 drives": continue without protection (storage daemons
   are masked on purpose).
3. Network backup: Network app → Settings → System → Backups → restore the
   `.unf` ([restore under load](#restore-under-load)).
4. Remote Access on (Control Plane → Console). Install Protect from the app
   list. Set the Network autobackup schedule (daily, keep 7) and the console
   backups (Control Plane → Backups → Automatic Backups, here weekly, keep 10),
   then "Backup Now" once: `/data/unifi-core/config/backup.yaml` (inside the
   container) must show Protect `success: true`.
5. `extras/unas-apps/backup-unas.sh root@<UNAS>` — `uckp-os:live` now holds
   the installed apps.
6. Optional, an MJPEG camera (e.g. a door station) in Protect:
   `extras/unas-apps/mjpeg-camera/install-mjpeg-camera.sh root@<UNAS> --ip <CAM_IP> --url <MJPEG-URL> --up`,
   then adopt it ([README](../extras/unas-apps/README.md#mjpeg-camera-in-unifi-protect)).
   From a recovery set the stack comes back with its `.env` and patched
   go2rtc; Protect keeps the adoption in its own backup.

### 9. Devices

Adopted switches and APs inform `http://<controller-ip>:8080/inform`. Keeping
the old controller address for UniFi OS avoids any re-adoption. Otherwise on
each device: `ssh <user>@<device>` (credentials: Network app → device SSH
authentication) and `set-inform http://<UCKP_IP>:8080/inform`.

### 10. Check

Verified on 2026-10-23 after a reboot with host tuning active: log RAM disks
mounted (about 4 MB in use), UniFi OS started from `uckp-os:live` with Network
and Protect in four minutes, all adopted devices reported again about two
minutes after the Network app was ready (they back off while the controller
is away), Remote Access connected, RAID resync resumed where it stopped.
LoxBerry 3.0.1.3 → 4.0.0.15 the same day with `update-loxberry.sh … 4`: about
12 minutes during the resync, every update script without warnings, the
container recreated from `loxberry-unas:live` kept the plugin packages, all
Shellys reconnected to the broker and the gateway kept forwarding.

- `https://<UCKP_IP>/`: UniFi OS up, Remote Access on, devices online.
- Inside: `docker exec unifi-os systemctl --failed` shows at most
  `analytic-report.service` (usage reports, not needed).
- `docker exec unifi-os timedatectl status`: "System clock synchronized: yes",
  "NTP service: active".
- `cat /proc/mdstat` on the host: arrays clean or resyncing; `free -m`: swap use
  low.
- `unas-monitor --status` on the host (after step 11): every check of the
  monitor, "Ergebnis: 0 Problem(e)".
- Make a recovery set and copy it off-box.

### 11. Monitoring (Telegram)

`extras/unas-host/install-monitor.sh root@<UNAS> --telegram --test` installs
`unas-monitor` on the host with a timer (every 5 minutes, Nice 19). It sends a
Telegram message (German, with host name and time) when something is down or
abnormal — once it was seen in two runs in a row (no flapping), again every
6 hours while it lasts, and "wieder OK" when it is gone. Without `--telegram`
it only logs to the journal.

1. Bot: in Telegram open **@BotFather**, `/newbot`, choose a name and a
   username ending in `bot`. BotFather answers with the token
   (`123456789:AA…`).
2. Mac: `install-monitor.sh root@<UNAS> --telegram --test`, paste the token
   (input hidden). When asked, open the new bot in Telegram and send it any
   message (tap *Start*), then press Enter: the UNAS takes the chat from the
   bot's newest message (`getUpdates`). Typing a chat id works too (groups:
   negative number). `--test` sends a message with the current state.
3. Run the same command again to change the token or the chat.

Token and chat id live only in `/etc/unas-monitor.conf` on the host (root,
mode 600, SD overlay). They travel from the Mac over stdin, curl reads its
configuration (URL with the token) from stdin, `backup-unas.sh` excludes the
file: never in this repository, on a command line, in a log or in the recovery
set. The same file takes optional settings (all of them: the head of
`/usr/local/sbin/unas-monitor`), e.g. `IGNORE_CONTAINERS="<name>"` for a stack
stopped on purpose, `IGNORE_FAILED`, `GRACE_MIN`, `GRACE_MIN_UNIFI_OS`,
`DISK_MAX_PCT`, `TEMP_MAX_C`.

On the host: `unas-monitor --status` (every check, sends nothing),
`--dry-run` (a timer run that prints the message instead of sending it; own
state), `--test`, `journalctl -u unas-monitor`. To try an alarm without
stopping anything, add a check for something that does not exist:
`unas-monitor --dry-run --simulate container:ghost` (also `unit:<unit>`,
`unit:<container>/<unit>`) twice gives the alert, a plain `--dry-run` then
"wieder OK".

What it checks — read-only, it never starts, stops or changes anything:

| Where | Checks |
| --- | --- |
| Host | `systemctl --failed`; `unas-docker`, `unas-netns-guard`, `unas-volatile-logs`, `unas-log-trim`, `var-tmp.mount`, `unas-backup.timer`, `unas-sd-image.timer`, `unas-fan-config` (when enabled) active and enabled; UniFi OS/Drive: `unifi-core`, `unifi-drive`, `unifi-directory`, `ulp-go`, `uos-agent`, `unifi-identity-update`, `postgresql@14-main`, `nginx`, `smbd`, `ssh`, `usd`, `ustated`, `usdbd`, `uhwd`, `rclone-rcd`, `earlyoom`, `cron`, journald, timesyncd; restart loops; UniFi OS state (`/api/system`); NTP sync |
| Storage | an array degraded or a member faulty (a resync or check is shown, never an alarm); pool mounted and writable; Btrfs error counters; pool, `/`, `/data` (SD card) and `/run` at 90 % |
| Hardware | less than 150 MB memory available, swap at 90 %; the CPU at 85 °C, any other sensor at 90 °C or a sensor alarm; a drive at 55 °C (SMART values from `/run/ustd/hw_polling.cache`, which UniFi's `uhwd` polls anyway, so no extra disk access) or those values older than 30 min; a fan that stops while the fans are driven |
| Containers | every container the stacks deploy (`docker compose config` of `data/stacks/*` and `dockge/`; services in inactive profiles such as the standalone controller are not expected) exists, runs, is not restarting or unhealthy, has no restart loop and still has its network interface; Docker answers |
| UniFi OS | `unifi-core`, `unifi` (Network), `unifi-protect`, `mongodb`, `unifi-mongodb`, `postgresql@14-main`/`14-protect`, `nginx`, `ulp-go`, `unifi-directory`; failed units (except `analytic-report`); Network `/status` (server running, database connected); UniFi OS state and, with Remote Access on, the cloud connection; Protect `controllerStatus` READY |
| LoxBerry | `apache2`, `mosquitto`, `cron`, `loxberry` and every other enabled service (plugin daemons such as Daikin Onecta); the MQTT gateway process (`mqttgateway.pl`); the web interface answers; failed units |

Right after a boot, a container start or a unit start, something that is not
up yet counts as starting: 15 minutes, UniFi OS 60 minutes (Protect's
migrations take up to ~45). A unit still activating after that is reported.
Checks inside containers use `docker exec` — the host cannot reach the macvlan
addresses. Nothing is written to the SD card: state in `/run/unas-monitor`
(gone after a reboot; the first run after a boot sends a short notice),
output in the journal (RAM). A run takes 4–8 seconds.

## Pitfalls and solutions

### Conversion

| Symptom | Cause | Solution |
| --- | --- | --- |
| `storage topology did not settle` after the reset | more than one drive inserted | remove all drives during the conversion |
| converter refuses UniFi OS 6.x | needs 5.1.33 | `tools/downgrade-to-5.1.33.sh`, auto-updates off first |
| `ACCOUNT_NOT_EXIST_LOCALLY` / HTTP 401 at unregister | not the owner account / first user picked | sign in as owner; fixed in this fork (owner looked up) |
| no MFA prompt, HTTP 400 on email MFA | identity service already sent the code | fixed: the code is asked for |
| pasted MFA code empty or garbage | bracketed paste | fixed in this fork |
| `Permission denied (publickey,keyboard-interactive)` | `pam_faillock` locked root after 3 failures | wait 3 min or `faillock --user root --reset` |
| unpacking the UNVR rootfs on the Mac breaks | case-insensitive APFS | unpack/import on the NAS (`/boot/firmware/rootfs`) |
| Docker Desktop crashes, builds fail | Mac disk full | keep ≥ 10 GB free |

### Host (UniFi OS 5.1.33, kernel 4.19)

| Symptom | Cause | Solution |
| --- | --- | --- |
| ~2 GB/day written to the SD card | persistent journal, syslog files, UniFi Drive's notificationManager logs disk iostat events (~80 MB/day), Postgres checkpoints every 5 min, /var/tmp and Samba sockets on the overlay | `install-host-tuning.sh`: journal in RAM, logs on small tmpfs mounts (16/4 MB upper bounds, RAM used only for content), trimmed every 5 min (rotated files deleted, logs over 2 MB emptied — `logrotate.timer` does not run on this host), Postgres checkpoints every 30 min |
| still ~450 MB/day on the SD card after the first round, `/data` grows by ~29 MB/day (full in about three months) | UniFi Drive samples remote-connection statistics every ~5 s into its Postgres table `connections` (database `unifi-drive`) and never deletes them (~8 MB/h of page and WAL writes); the ext4 journal of `/data` commits every 5 s (~6 MB/h) | `install-host-tuning.sh`, second round: `unas-drive-stats-trim` (daily 04:40 and 15 min after boot) keeps the table unlogged and 3 days long — Postgres empties an unlogged table after an unclean shutdown, which only loses statistics; `/data` remounted with `commit=60` (fsync still forces a commit) |
| a RAM log mount runs full (ulp-go writes many small logs) | no single file exceeds 2 MB, so nothing is trimmed | ulp-go's mount is 8 MB; `unas-log-trim` empties files over 256 kB once a mount is 75 % full |
| automatic updates on the host? | — | none: the conversion turns apt's periodic jobs off, UniFi OS logs "No auto-update scheduled" and applications have no schedule; recheck after changing update settings in the console |
| everything slow, high iowait | initial RAID 6 resync on HDDs, swap on the same disks | let it finish; for heavy jobs pause it: `echo frozen > /sys/block/md3/md/sync_action`, resume with `echo idle` |
| swap mirror `md0` shows `[4/2]` | its rebuild waits behind the md3 resync | finishes on its own after md3 (or while md3 is paused) |
| memory pressure, swap full | 4 GB for Drive, three UniFi OS instances and two controllers during the migration | run one UniFi OS (the UCKP container) and stop the rest; host `earlyoom` kills only below 250 MB RAM and 10 % swap |
| update offers for the host | — | do not update the host OS (see README "OS updates"; the conversion pins 5.1.33) |
| fans stay at ~23 % (~1,800 rpm) with the CPU at 81–85 °C and the drives at 47–50 °C; UniFi Drive shows no fan mode (its API: "the fan control is not allow in this console"); a PWM value written to the hwmon device is taken back within seconds | Ubiquiti's `uhwd` runs a PID controller with the board's set points (UNVR4, `ea1a`: CPU 83 °C, drives 48 °C) from `config.fan` in ustd's status database; no profiles on this board | `install-fan-setpoints.sh` (measured with 75/44: fans 45–60 %, CPU 88 → 78 °C in two minutes under load) |

### Docker on this kernel

| Symptom | Cause | Solution |
| --- | --- | --- |
| every container fails: `bpf_prog_query(BPF_CGROUP_DEVICE)` | cgroup v2 without BPF | crun with `--cgroup-manager=disabled` (no per-container limits) |
| no bridge networks, no port publishing | no veth/bridge/netfilter | macvlan `unas-lan`, one LAN address per app (`macvlan.ko` built by `tools/build-modules.sh`) |
| no DNS in containers | embedded DNS needs iptables | mount `resolv.conf` with `LAN_DNS` |
| systemd containers: "Failed to mount API filesystems" | no cgroup of their own | `cgroup: host` and `/sys/fs/cgroup:rw` |
| controller unreachable after the database container restarted | `network_mode: service:` joins a namespace that died | the database owns the address; `unas-netns-guard` restarts orphans (quiet loop) |
| `/tmp` not writable in a container | a tmpfs with any option loses mode 1777 | `/tmp:exec,mode=1777` |
| the NAS cannot reach its own apps | macvlan isolates the parent | use another LAN device |
| BuildKit errors on the NAS | old kernel | `DOCKER_BUILDKIT=0` |

### Reaching the NAS from the Mac

| Symptom | Cause | Solution |
| --- | --- | --- |
| NAS and apps unreachable, gateway reachable | a VPN claims `192.168.0.0/24` and `192.168.1.0/24` (more specific than the local /23) | two small network routes over the LAN: `sudo route -n add -net <subnet>/29 -interface en0` (covering the app addresses and the NAS) |
| after a host route every address resolves to the Mac's own MAC | on macOS `route add -host … -interface en0` uses the Mac's MAC as next hop | use `-net …/29` routes, not host routes |

### LoxBerry

| Symptom | Cause | Solution |
| --- | --- | --- |
| installer builds LoxBerry 4 / PHP 8.4 fails | upstream installer moved to Debian 13, whose systemd refuses the UNVR's cgroup v1 | build 3.0.1.3 on bookworm from the pinned installer (`loxberry/base`), then update in place: LoxBerry 4 still ships a Debian 12 package list (`packages12.txt`) and keeps PHP 7.4 for Apache |
| update page offers no 4.x | the updater stays within the current major version until `Update.max_version` allows the next | `loxberry/update-loxberry.sh root@<UNAS> 4` sets it, as "allow upgrade" on the update page does |
| packages a plugin or update installed (e.g. ffmpeg for Intercom) are gone after the container is recreated | apt installs go into the container layer; only `/opt/loxberry` is a volume | the stack runs `loxberry-unas:live`; `unas-backup`, `install-on-unas.sh --up` and `update-loxberry.sh` commit the container to it; `--images` never overwrites a `:live` image on the UNAS |
| LoxBerry and its plugins update themselves once cron runs (core weekly, plugins daily) | core `Update.Installtype=install`; plugins installed from release URLs get autoupdate 3 ("install releases") | notify only: Updates page → "notify" with an interval (setting the type without an interval removes the weekly check), Plugin management → each plugin "notify" (2); then update deliberately with `update-loxberry.sh` (rollback point first) |
| LoxBerry's cron jobs never run (log maintenance, plugin jobs such as Intercom and Alexa2Lox, update check) | the installer runs with a stubbed `systemctl` in the image build and leaves `cron.service` disabled | enabled in `loxberry/Dockerfile`; in an existing container: `systemctl enable --now cron`, then commit `:live` (`unas-backup` does) |
| every LoxBerry start sets kernel values of the NAS, may load modules and replays udev events for all host devices | the container is privileged (systemd), so `/proc/sys` and `/sys` are writable and `systemd-sysctl`, `systemd-modules-load` and `systemd-udev-trigger` run as on a real machine | masked in `loxberry/Dockerfile`; in an existing container: `systemctl mask systemd-sysctl systemd-modules-load systemd-udev-trigger`, then commit `:live` |
| LoxBerry's logs and cron run on UTC, hours off local time | the base image's time zone is UTC; with DietPi's marker in the image LoxBerry skips its hourly time job and every start only re-applies `/etc/timezone` | build argument `LB_TIMEZONE` (`build-images.sh` passes the Mac's); in an existing container: the zone into `/etc/timezone`, `dpkg-reconfigure -f noninteractive tzdata`, restart cron, Apache, the plugin services and the MQTT gateway, commit `:live`; set the same zone on LoxBerry's time page |
| saving LoxBerry's time page would set the NAS clock | it runs `sudo ntpdate`, and the container is privileged (Docker ignores `--cap-drop SYS_TIME` there) | `loxberry/Dockerfile` diverts `ntpdate` to a query-only wrapper (`dpkg-divert`, survives package updates); never choose "time from the Miniserver" there (runs `date -s`) |
| MQTT gateway gone after `mqtt-handler.pl action=restartgateway` (no values reach the Miniserver, Loxone commands on UDP 11884 ignored) | as user `loxberry` the script kills the gateway, then cannot start it again (`su loxberry` asks for a password) | run it as root in the container (`docker exec loxberry bash -c 'set -a; . /etc/environment; set +a; /opt/loxberry/sbin/mqtt-handler.pl action=restartgateway'`); `pgrep -fa mqttgateway.pl` must show the process afterwards |
| some Shellys stay offline for minutes after LoxBerry restarts | the Shelly firmware retries the broker with growing pauses | wait up to about 4 minutes (2026-10-24: six back within a minute, the last two after 3½); `http://<shelly>/rpc/Mqtt.GetStatus` shows `connected` |
| plugin install seems stuck for minutes | its apt dependencies unpack slowly (dpkg syncs every file; RAID 6, resync) | wait; `log/system/plugininstall/<plugin>.log` and `pgrep -fa dpkg` in the container show progress |
| Alexa2Lox: login with user and password fails | Amazon only accepts a refresh token now | run `alexa-cookie-cli` (adn77) on the Mac in a plain terminal: `-B 127.0.0.1 -q`, log in at `http://127.0.0.1:8080`, paste the `Atnr|…` token on the plugin page |
| `alexa-cookie-cli`: "Proxy Server could not be initialized" | port 8080 is taken on the Mac (`-d` shows `EADDRINUSE`) | `-P <free port>` and open that port instead |
| `alexa-cookie-cli -d` prints the refresh token, access tokens and Amazon session cookies | debug output | leave `-d` off; never run it where output is logged or shared; if it leaked: deregister the device "alexa_cookie_cli" on amazon.de, change the password with "sign out everywhere", then fetch a new token |
| SecurePIN visible in the container's process list during a plugin install | `plugininstall.pl` takes it as a parameter | change the PIN afterwards if that matters: `set-passwords.sh` (Enter keeps the password) |
| `dietpi` user missing, PHP 7.4 repo key fails | container base lacks them | created in the Dockerfile, `gnupg` added |
| default password is public | — | change it; SSH for `loxberry` with keys only |
| changing the password in the web interface fails | it asks for the old password and SecurePIN; the installer in the image build set random ones | `loxberry/set-passwords.sh` sets them as root in the container |
| LoxBerry tools fail via `docker exec`: `Can't locate LoxBerry/System.pm in @INC` | `docker exec` does not read `/etc/environment` (`PERL5LIB`, `LB*` paths) | `set -a; . /etc/environment; set +a` first (the scripts do) |
| MQTT broker open to the LAN without login (`allow_anonymous true`) | LoxBerry's MQTT basics were never saved, so no broker user exists | `loxberry/shelly-mqtt.sh` sets user and password and runs `mqtt-handler.pl action=mosquitto_set`; it checks that anonymous logins are refused |
| an extra MQTT user (e.g. for Home Assistant) disappears after saving LoxBerry's MQTT settings | LoxBerry rewrites `/etc/mosquitto/conf.d/mosq_passwd` with only its own broker user | `extras/unas-apps/loxberry/mqtt-user.sh root@<UNAS> <user> \| pbcopy`: stores the user's hash in `config/system/mosquitto/extra_users` (LoxBerry volume) and installs `mosq-extra-users.path`, which puts it back after every rewrite and reloads Mosquitto |

### UniFi OS in a container (Cloud Key Gen2 Plus)

| Symptom | Cause | Solution |
| --- | --- | --- |
| no Network app on the UNVR or UNAS identity | UniFi OS installs only the apps its model allows | UCKP: Network + Protect, ARMv8.0 like the AL-324, no gateway hardware needed (UDM/UDR/UCG need router hardware) |
| boot hooks fail: mount `/dev/mtdblock6` | the host's `/proc/mtd` lists the UNVR flash | empty `/proc/mtd` bind mount; partition hooks removed |
| `systemd-firstboot` fails | no console | masked |
| Network app: "Failed to identify UniFi-OS host" | it matches architecture, model **and CPU ID**; the AL-324 ID belongs to the UDM Pro | identity carries the Cloud Key's CPU ID `410fd034-00000000` |
| Network app: "Invalid uuid version - 4" | board UUIDs of real devices are version 5 | v5 UUID derived from the MAC |
| UniFi OS state `error`, "Error reading network data for eth0" | it reads DNS from systemd-resolved (masked) | tmpfiles link `/run/systemd/resolve/resolv.conf` → `/etc/resolv.conf`; after earlier app failures restart `unifi-core` once |
| storage step: 0 B, "at least 2 drives" | storage daemons masked on purpose | continue without protection; never unmask `usd`/`ustated` |
| after every container start Protect has no folders on `/srv`, its database is recreated, cameras cannot be adopted; journal: `50-srv-link … remove unexpected /srv folder` | the boot hooks `bootup-bottom/50-srv-link` (`srv-gen`) and `10-scan-dot-srv` rebuild `/srv` from the storage daemon's view — no disk, so they wipe it | both removed in the image (with their `bootup-top` counterparts); in a running container remove them, `systemctl restart unifi-protect`, commit to `uckp-os:live` |
| console backup without Protect: `/data/unifi-core/config/backup.yaml` shows `protect: success: false`, `…/api/ucore/backup/export failed, status: 500 … Could not save backup in directory /data/unifi-core/backups/<id>/backup/protect/` | Protect ran on the `/srv` those hooks had wiped (row above): its export reads its device certificate (`/srv/unifi-protect/data/devices.crt`) and its database, both gone. Not permissions: unifi-core creates the directory with mode 777 for Protect's user | fixed with the hooks. Test Protect's export inside the container without a login: `d=/data/unifi-core/backups/selftest/backup/protect/; mkdir -p $d && chmod 777 $d && curl -s -w '%{http_code}\n' -H 'Content-Type: application/json' -d "{\"dir\":\"$d\"}" http://127.0.0.1:7080/api/ucore/backup/export; ls $d; rm -rf /data/unifi-core/backups/selftest` (200, about 30 files); then "Backup Now" |
| unifi-core: "Scheduled backup inactive and no recovery snapshot to refresh; no CronJob scheduled" | Automatic Backups off (as after the setup) | Control Plane → Backups → Automatic Backups; then `settings.yaml` has `autoBackupEnabled: true` and the log "Building backup schedule cron: … (user schedule)" after every unifi-core start |
| Network app killed during start, restart loop | start > 15 min under load | systemd start timeout 45 min (in the image) |
| Protect restart loop: `Failed with result 'timeout'`, `relation "nvrs" does not exist` | a first start (empty database) runs every migration, longer than Protect's 5 min start timeout | 45 min (in the image) |
| first Protect start takes about an hour | 886 migrations (4.x → 7.3), each with fsyncs on RAID 6 HDDs | only while its database is new: `ALTER SYSTEM SET fsync = off` + `SELECT pg_reload_conf()` on port 5433 (as `postgres` inside the container), and once Protect is active `ALTER SYSTEM RESET fsync`, reload, `CHECKPOINT` |
| `uid-agent` crash loop: "Dirty database version …" | killed during its first migration (90 s limit) | 25 min / 1200 s in the image; repair: stop it, `DROP SCHEMA public CASCADE; CREATE SCHEMA public;` in its database `uid` (only while it never ran), start |
| Remote Access cannot be enabled: "Timeout when waiting for ClockSynchronized" | it needs `NTP=yes` and `NTPSynchronized=yes`; timesyncd is masked (the host owns the clock) | no-op unit registered in `ntp-units.d` (in the image) |
| UI: IP configuration, fallback IP, SSH have no effect; Shut Down restarts | network, SSH and power services are masked; Docker restarts the container | change the address in the stack's `.env`; **never Factory Reset** (wipes the container's data) |
| Protect missing after recreating the container | UniFi OS installs apps into the container layer, not into the volumes; the clean build `uckp-os:6.0.11` lacks them | the stack runs `uckp-os:live`; `install-on-unas.sh --up` and `backup-unas.sh` commit the running container to it first. Deploying a rebuilt base (`docker tag uckp-os:6.0.11 uckp-os:live`) drops installed apps — reinstall them in UniFi OS |
| UniFi OS update offered | — | do not update UniFi OS inside the containers; rebuild from newer firmware instead |
| the UniFi OS container updates itself (firmware and apps, weekly, Sunday 00:00) | the setup wizard turns automatic updates on ("Firmware auto-updates enabled", `firmware.yaml` `autoUpdate.schedule` set, `includeApplications: true`) | turn them off right after setup: Settings → Control Plane → Updates (UniFi OS and applications); check that `/data/unifi-core/config/firmware.yaml` shows `autoUpdate: schedule: null` |
| UniFi devices update their firmware at night | Network's device auto upgrade (on by default, 03:00) | optional; turned off here (Network → Settings → System → updates) to update deliberately |
| cameras update their firmware at night; Protect 7.3 has no switch for it | Protect's device auto-update (`nvrs."deviceFirmwareSettings"`, on, daily 03:00) has no UI any more | in the database with Protect stopped (next row): `update nvrs set "deviceFirmwareSettings" = ("deviceFirmwareSettings"::jsonb \|\| '{"isAutoUpdateEnabled": false}')::json` |
| Protect hides recording quality, bitrate and retention ("insert compatible storage") and keeps resetting fps/bitrate | the container's storage is an image on the pool, not a Cloud Key disk; the channels run with `autoFps`/`autoBitrate` | set the camera's channel in `cameras.channels` (e.g. high channel `fps` 15, `bitrate` 2000000, `autoFps`/`autoBitrate` false) with Protect stopped; recording continues, about 1 min gap |
| database change for Protect does not stick or psql: "the database system is shutting down" | stopping `unifi-protect` also stops its database `postgresql@14-protect`, and Protect writes its state on start | inside the container: `systemctl stop unifi-protect`, then `systemctl start postgresql@14-protect`, wait for `pg_isready -h 127.0.0.1 -p 5433`, change with `psql -p 5433 -U postgres -d unifi-protect`, then `systemctl start unifi-protect` (back up the old value first) |
| installing Protect takes ~45 min, "unpacked" for a long time | dpkg syncs every file, slow on RAID 6 HDDs | wait; the image sets `force-unsafe-io` for later installs and updates |

### MJPEG camera in Protect

| Symptom | Cause | Solution |
| --- | --- | --- |
| advanced adoption says "invalid credentials" although they are right | the dialog has no port field; Protect looks for ONVIF on go2rtc's port 1984 | keep go2rtc's API on `:1984` (it keeps that port for ONVIF and snapshots afterwards) |
| Protect shows 1920×1080, 30 fps, 8 Mbit/s | go2rtc's ONVIF answers are fixed, Protect reads them once at adoption | the stack mounts a go2rtc patched with the real values (`patch-onvif-values.sh`); for a camera adopted before: with Protect stopped (its database alone, see "database change for Protect" above), set `width`/`height`/`fps`/`fpsValues`/`bitrate` of channel 0 in `cameras.channels` |
| H.264 stream at 25 fps and high CPU although fewer frames are kept | ffmpeg assumes 25 fps for MJPEG and fills the RTSP output up with copies | `-r` with the target rate on the output (in `go2rtc.yaml`) |
| go2rtc takes ~35 % CPU | its own MJPEG reader hands the full MJPEG to ffmpeg over internal RTSP | ffmpeg reads the camera itself (`#input=camera`) |
| camera ignores `?fps=` / `?resolution=` (Loxone Intercom: always ~19 fps 1280×720) | — | thin out in ffmpeg before decoding (`--keep-every`) |
| MJPEG from the camera stalls for up to 20 s at the NAS only (fine to a Wi-Fi client); many out-of-order and duplicate TCP segments (`TCPOFOQueue`, `TCPDSACKOldSent` in `/proc/net/netstat`) | the camera's switch port forced to 100 Mbit/s full duplex without autonegotiation: the camera falls back to half duplex (UniFi showed millions of `rx_errors` on that port); fast ACKs from the wired NAS collide, a Wi-Fi client hides it | set the port to "Auto" in UniFi Network |

### Restore under load

| Symptom | Cause | Solution |
| --- | --- | --- |
| restore at ~80 % for minutes | the app imports into `ace_restore`, then drops the old database and restarts | normal; wait |
| "After-import cleanup failed" / "Failed to restore backup" | dropping the old database blocks MongoDB 3.6 for > 3 min on RAID 6 HDDs (fsync), the app's MongoDB timeout is 3 min | stop other controllers, pause the RAID resync, set `db.mongo.timeout=900` in `/data/unifi/data/system.properties` (inside the container), `systemctl restart unifi`, restore again, remove the line |
| crash loop after setting the timeout | the value is not in milliseconds (`900000` overflows) | use `900` |
| failed restore | — | nothing is lost: the running app keeps an empty `ace`, the backup stays in `ace_restore` until the next attempt |

### Monitoring

| Symptom | Cause | Solution |
| --- | --- | --- |
| Protect's `errors.log` grows with `401 GET /api/ Unauthorized` | an unauthenticated health request is logged as an error (4 lines per request) | ask `/api/ucore/status` instead (what `unifi-core` polls; `controllerStatus`) |
| `analytic-report.service` failed in UniFi OS | usage reports; fails on every start, not needed | ignored by default (`IGNORE_FAILED`) |
| UniFi OS `deviceState` is `setup` or `updateAvailable` | normal states | only `error` or an error code alarms |
| reminder every 6 h after a failed weekly backup | `unas-backup.service` stays failed until its next run | `journalctl -u unas-backup`, fix, then `systemctl reset-failed unas-backup` |
| a stack stopped on purpose alarms | every container the stacks deploy is expected | `IGNORE_CONTAINERS="<name>"` in `/etc/unas-monitor.conf` |
| `--telegram`: "Keine Nachricht an @… gefunden" | no message to the bot in the last 24 h (or the bot has a webhook) | send the bot a message and run again, or type the chat id |
| no message while the internet is down | Telegram unreachable | the monitor retries every run; the alert or "wieder OK" follows once it is back |

### Optional: UNVR Protect container

Before the Cloud Key container, Protect ran from the box's own UNVR 5.1.33
userland (`extras/unas-apps/protect/`). Its own pitfalls: identity and
`ubnt-tools`/`ustorage` wrappers; "no internet" until the interface is named
`enp0s1`; a crash loop on `/tmp` permissions; the button daemon `ubnd` masked;
after the first setup UniFi OS moves Protect's Postgres to `/srv` and Protect
needs one restart. It stays stopped and is only a fallback.

## Private system sheet

`SYSTEM.md` in `<pool>/.unas-apps/backup/` (also inside each recovery set)
lists this installation's values: addresses and MACs, pool path, console
identities, image IDs, versions, schedules and where credentials are kept (not
the credentials). Keep a copy off-box together with the recovery set.
