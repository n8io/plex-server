# plex-trash-clean

Nightly (04:45 box time) guarded "Empty Trash" for every Plex library. Plex's own
auto-empty stays **off**: if the rclone/EncFS mount drops, Plex would mark the whole
library missing and auto-empty would wipe it.

Install / update: `./addons/plex-trash-clean.sh` (copies to `/usr/local/sbin`, writes
`/etc/cron.d/plex-trash-clean`). Log: `/var/log/plex-trash-clean.log`.
Config: `/etc/plex-trash-clean.env` (root 600): `PUSHBULLET_TOKEN`, optional
`MAX_PCT` (5), `MAX_ITEMS` (200), `REALERT_DAYS` (7), `DRY_RUN=1`.

## Guards (a section failing one is skipped, never partly emptied)

1. Media mount is mounted.
2. Every library root lists non-empty within 30 s (else skip ALL).
3. Trashed versions < `MAX_PCT`% of the library and < `MAX_ITEMS`.
4. Every trashed file is absent on disk. If one exists, the section is rescanned
   instead (Plex then un-trashes it) and an alert is sent.

## What counts as trashed

Plex 1.43 ignores `?trashed=1`, so the script reads `deletedAt` from
`/library/sections/<id>/all?type=1|4&includeDeleted=1`:

- whole item (movie/episode) has `deletedAt` → all of its files;
- otherwise only the Media (version) or Part that has `deletedAt`.

The second rule matters for upgrades. When Sonarr/Radarr replace a file, Plex keeps
the episode and marks only the old version deleted. Until 2026-11-14 the script
checked every file of such an episode, counted the live replacement as "trashed but
still on disk", and skipped + alerted every night (VisionQuest S01E02-04).

## Alerts

Pushbullet link pushes with the reason and a link to the library in Plex. The same
message is pushed at most once every `REALERT_DAYS` days (always logged).
