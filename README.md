# plex-server
A hand full of scripts to setup your Plex Media Server and keep it running smoothly

## Getting started

1. ssh into your Plex Media Server
```
ssh -i ~/.ssh/id_rsa -L 32400:localhost:32400 root@<your.pms.public.ip>
```
1. Clone this repo
```
apt-get install -y git && \
cd / && git clone https://github.com/n8io/plex-server.git && cd plex-server
```
1. Initialize
```
./install.sh
```

## Day-to-day scripts

All run from `/plex-server` on the server (root's shell starts there).

| Script | What it does |
|---|---|
| `scripts/plex-scan.sh -t alone` | Scan just one show/movie folder into Plex — fuzzy name match, `-t`/`-m` to limit to TV or movies, `-f` to also refresh metadata, `-n` dry run, `-l` list matches. Works for media Plex hasn't seen yet. |
| `scripts/cache-status.sh [path]` | Show which media is cached on local disk by rclone (`100%` = plays without touching the cloud). |
| `scripts/cycle-mount.sh` | Remount the cloud drive (rclone) — what the nightly cron and `mount-check.sh` use. |
