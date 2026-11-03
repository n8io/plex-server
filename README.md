# plex-server

Scripts that turn a bare Ubuntu/Debian box into a Plex Media Server whose media
lives in the cloud — mounted with **rclone**, transparently decrypted with
**EncFS**, cached on local disk, and kept alive by cron — plus the day-to-day
tools for running it.

## How it fits together

```mermaid
flowchart LR
    cloud[("Cloud drive<br/>(rclone remote)<br/>encrypted files")]
    rclone["rclone mount<br/>read-only, VFS full cache<br/>/mnt/x/encrypted"]
    cache[("Local disk cache<br/>/home/rclone-cache")]
    encfs["EncFS<br/>/mnt/x/decrypted"]
    plex["Plex Media Server"]
    users(["Viewers"])
    cloud --> rclone
    rclone <--> cache
    rclone --> encfs --> plex --> users
```

- A separate machine (the "processing server") encrypts new media with EncFS and
  uploads it to the cloud drive. This box only ever **reads**.
- `rclone mount` exposes the encrypted cloud folder at `$ENC_DIR_LOCAL` and keeps
  every chunk it reads in a local cache (`--vfs-cache-mode full`, LRU up to
  `RCLONE_CACHE_MAX_SIZE`). Anything played once is served from disk after that,
  and seeks inside cached files are instant. New uploads show up within about a
  minute (`--poll-interval 1m`).
- EncFS mounts on top of that and presents plain filenames and content at
  `$DEC_DIR_LOCAL`. Plex's libraries point there.
- systemd runs both layers (`rclone-media`, then `encfs-media` bound to it),
  brings them up at boot, and restarts them if they die; Plex starts after
  them so it never scans an empty folder. A second, uncached rclone mount
  (`rclone-photos`) serves the workout videos at `$PHOTOS_DIR_LOCAL`.
- Cron runs `mount-check.sh` every 5 minutes to catch a mount that hangs
  without dying.

## Layout

```
install.sh                 runs the setup/ steps in order
setup/
  00.bashrc.sh             interactive: writes .env, stores EncFS/rclone creds, hooks root's .bashrc
  01.dependencies.sh       apt packages, latest stable rclone (checksum-verified), fusermount3 shim
  02.os-settings.sh        sysctl tuning in /etc/sysctl.d/90-plex.conf (BBR, TCP buffers)
  03.cron-jobs.sh          installs the cron schedule (idempotent, removes retired jobs)
  04.plex.sh               Plex from its official apt repo, unattended OS + Plex updates
  05.encryption.sh         installs and starts the systemd mount units
  06.plex-settings.sh      applies Plex's server settings via its API and reads them back
  07.tailscale.sh          joins the tailnet, serves Plex Scan UI to it
  08.lockdown.sh           keys-only SSH; firewall allows only Plex (32400), SSH and the tailnet
systemd/
  rclone-media.service     rclone mount of the encrypted media (Type=notify)
  encfs-media.service      EncFS on top; stops and restarts with rclone-media
  rclone-photos.service    rclone mount of the workout videos
  plexmediaserver-override.conf   Plex waits for the mounts; TimeoutStopSec=600
  plex-scan-ui.service     hardened unit for the Scan UI
scripts/
  mount.sh                 the rclone mount command (all flags live here): mount.sh media|photos
  encfs-mount.sh           the EncFS command
  cycle-mount.sh           restart a mount through systemd: cycle-mount.sh [media|photos]
  mount-check.sh           are the mounts readable? if not, cycle them
  logs-cleanup.sh          nightly log truncation
  plex-scan.sh (+ .py)     scan one show/movie folder into Plex, fuzzy by name
  cache-status.sh          what's on local disk, per file, in decrypted names
  helper-functions.sh      encode/decode filenames with encfsctl (sourced by .bashrc)
addons/
  plex-scan-ui/ (+ .sh)    web page to scan one show/season/movie; .sh installs it
  tautulli.sh              Tautulli stream history, tailnet only (https://<node>:8443)
  extended-personal-media-scanner.sh   scanner for libraries without standard metadata
```

Generated on the server, never committed: `.env` (paths and binaries), `logs/`,
and the credential files `.env` points at.

## Getting started

1. SSH in (forward 32400 so you can reach Plex's web UI at `http://localhost:32400/web` before Remote Access is set up):

   ```
   ssh -i ~/.ssh/id_rsa -L 32400:localhost:32400 root@<your.pms.public.ip>
   ```

2. Clone to `/plex-server` — the scripts assume that path:

   ```
   apt-get install -y git && cd / && git clone https://github.com/n8io/plex-server.git && cd plex-server
   ```

3. Run the installer and answer the prompts:

   ```
   ./install.sh
   ```

   You'll be asked for the remote folder that holds the encrypted media, where to
   mount things (default `/mnt/x`), your EncFS password, the contents of
   `encfs.xml` and of `rclone.conf` from the processing server. Existing values
   are kept if you press Enter.

4. In Plex (`Settings → Libraries`) add libraries under `$DEC_DIR_LOCAL`
   (e.g. `/mnt/x/decrypted/tv`, `/mnt/x/decrypted/movies`). In
   `Settings → Remote Access`, manually specify port 32400 — automatic port
   mapping doesn't work on a datacenter box.

### `.env`

`00.bashrc.sh` writes `/plex-server/.env`, which every script sources. The
important variables:

| Variable | Meaning | Default |
|---|---|---|
| `ENC_DIR_REMOTE` | folder on the rclone remote holding encrypted media | `/encrypted` |
| `MOUNT_DIR` | parent of the two mount points | `/mnt/x` |
| `ENC_DIR_LOCAL` / `DEC_DIR_LOCAL` | rclone mount / EncFS mount | `$MOUNT_DIR/encrypted`, `$MOUNT_DIR/decrypted` |
| `ENCFS_CREDS` / `ENCFS6_CONFIG` | EncFS password file / config | `/.encfs`, `/encfs.xml` |
| `RCLONE_BIN` | rclone binary | `/usr/sbin/rclone` |
| `RCLONE_CACHE_DIR` / `RCLONE_CACHE_MAX_SIZE` | local media cache (optional overrides) | `/home/rclone-cache`, `800G` |
| `PHOTOS_DIR_REMOTE` / `PHOTOS_DIR_LOCAL` | workout videos mount (optional overrides) | `/_/decrypted/workouts`, `/photos/Workouts` |

### Disk layout

The cache is disposable (it refills from the cloud), so it doesn't need RAID.
On a two-drive box, mirror only a small OS + Plex partition (~100 GB) and give
the rest of both drives to the cache (RAID 0 or one cache partition per drive
via separate mounts), then point `RCLONE_CACHE_DIR` at it. Cache size is what
decides how often plays hit the cloud; keep `RCLONE_CACHE_MAX_SIZE` ~10% under
the partition size.

`.env` also defines `log_info` / `log_error` / `log_fatal`, which write to
`logs/*.log`.

## Cron schedule

Installed by `03.cron-jobs.sh` (won't duplicate entries on re-run):

| When | Job | Why |
|---|---|---|
| every 5 min | `scripts/mount-check.sh` | restart a mount that hangs without dying |
| daily 08:01 UTC | `scripts/logs-cleanup.sh` | truncate logs |

There is no nightly mount restart any more: it cut live streams and caused
cache read errors right after it ran, and the mounts weren't failing. Boot-time
mounting is systemd's job. Plex and OS security updates arrive through
`unattended-upgrades` (`04.plex.sh`); reboots stay manual.

## Day-to-day

All examples run from `/plex-server` (root's shell starts there).

### Get new media into Plex right away

```
scripts/plex-scan.sh -t alone                   # TV show, fuzzy name
scripts/plex-scan.sh -m super mario             # movie; ambiguous names prompt
scripts/plex-scan.sh game changer               # search every library
scripts/plex-scan.sh -f -t alone                # also refresh metadata of known episodes
scripts/plex-scan.sh "tv/adult/Alone/Season 13" # an explicit folder
scripts/plex-scan.sh -l -t gold                 # just list the matches
scripts/plex-scan.sh -n -y -m mutiny            # dry run, auto-pick best match
```

Scans **only that folder** (Plex's partial-refresh API), so it takes seconds
instead of a full library scan. Matching is done against the folders on the
mount, not Plex's database, so brand-new titles work. The server token is read
from Plex's own `Preferences.xml` at runtime. Hook it into the upload step on the
processing server and new episodes appear about a minute after they finish
uploading.

### See what's cached locally

```
scripts/cache-status.sh                         # everything in the cache
scripts/cache-status.sh "movies/release/Dune (2021)"
```

```
 cached       size  file
 100.0%    0.36 GB  tv/adult/Game Changer/Season 03/Game Changer - S03E09 ... .mkv
  37.3%    1.46 GB  movies/prerelease/The Super Mario Galaxy Movie (2026)/... .mkv
```

`100%` plays entirely from local disk. A partial figure is a file someone
started and stopped; the rest streams from the cloud on demand. To pre-warm a
title, read it once: `cat "/mnt/x/decrypted/movies/release/Dune (2021)/"*.mkv > /dev/null`.

### Mount maintenance

```
scripts/mount-check.sh        # health check (what cron runs); logs to logs/mount-check.log
scripts/cycle-mount.sh        # restart rclone + EncFS (systemctl restart rclone-media)
scripts/cycle-mount.sh photos # restart the workout videos mount
systemctl status rclone-media encfs-media rclone-photos
tail -f logs/rclone-media.log
```

`helper-functions.sh` (sourced into root's shell) gives you `encode <path>` and
`decode <path>` to translate between plain and encrypted filenames.

## Streaming performance notes

- Every stream that **Direct Plays** costs almost nothing; every transcode costs
  20–30 % of a CPU without hardware encoding. Keep the library H.264/AAC where
  possible, prefer text subtitles (image subtitles force a transcode), and have
  viewers enable Direct Play/Direct Stream and "Original" remote quality in their
  apps.
- `02.os-settings.sh` switches TCP to BBR and lets buffers grow for long-distance
  streams. It no longer sets web-server tuning (file-max, TIME_WAIT, 16 MB
  per-socket defaults): on a modern kernel those were lower than the defaults or
  wasted memory.
- `06.plex-settings.sh` turns off Plex jobs that read whole files from the cloud
  (thumbnails, loudness/music analysis, ad markers), moves transcodes to
  `/dev/shm`, and raises the database cache to 1 GB. Each setting is commented
  with why.
- The first play of a file is limited by the cloud provider's per-file download
  speed; subsequent plays and seeks come from the local cache.

## Access and lockdown

Only Plex (32400/tcp) is public. `08.lockdown.sh` turns off SSH passwords
(it refuses if root has no authorized key) and enables a firewall that also
allows SSH and anything arriving over Tailscale. Plex Scan UI
(`https://<node>.<tailnet>.ts.net`) and Tautulli (`:8443`) bind to localhost
and are served to the tailnet by `tailscale serve`.

Once `ssh root@<tailscale name>` works, close public SSH:
`SSH_TAILSCALE_ONLY=1 setup/08.lockdown.sh`. If you ever lock yourself out,
boot OVH's rescue mode from the control panel, then `ufw disable` and remove
`/etc/ssh/sshd_config.d/90-plex.conf` on the mounted disk.

## Rollback and recovery

- **Mount problems** — `scripts/cycle-mount.sh` (EncFS restarts with rclone);
  `journalctl -u rclone-media -u encfs-media` shows why. `mount-check.sh` and
  systemd do the restart automatically.
- **rclone upgrade regret** — install the previous binary at `$RCLONE_BIN` and
  cycle the mount; the cache directory can simply be deleted.
- **Plex data** — Plex keeps rolling copies of its database in
  `Plug-in Support/Databases/`. Back the whole `Plex Media Server` directory up
  off-box; the media itself is already in the cloud.

## Gotchas

- rclone ≥ 1.60 execs `fusermount3`. `01.dependencies.sh` creates a
  `fusermount3 → fusermount` symlink on FUSE 2-only hosts; if a fresh mount fails
  with "executable file not found", that's why.
- Plex's data directory is set by `PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR` in
  the systemd unit. Never edit `/lib/systemd/system/plexmediaserver.service`
  directly — `.deb` upgrades overwrite it. Overrides live in
  `systemd/plexmediaserver-override.conf`, installed by `05.encryption.sh`
  (`TimeoutStopSec=600`: Plex can take minutes to checkpoint a large database
  on stop, and a SIGKILL mid-write corrupts it).
- `mount.sh` no longer passes `--allow-non-empty`: mounting over leftover files
  hid failed unmounts. If a mount fails with "directory not empty", something
  wrote into the mount point while it was down; clear it and cycle the mount.
- The rclone mount is read-only by design. Plex features that write next to the
  media (Optimize, subtitle downloads into the media folder) won't work.
