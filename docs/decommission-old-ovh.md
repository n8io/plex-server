# Old OVH Plex box decommission (2026-11-17)

The original Plex server (OVH Canada bare metal, `158.69.124.112`, Ubuntu 16.10 EOL,
tailnet node `n8flix` / 100.77.221.111) was replaced by the current box
(`15.235.114.39`, tailnet `n8flix-new`) on 2026-11-04 (`scripts/cutover.sh`).
Its Plex stayed off as a fallback until it was cancelled.

## Checks before cancelling

Searched for `158.69.124.112`, `158-69-124-112` (plex.direct), `100.77.221.111` and the
old tailnet name everywhere that talks to Plex. Nothing live pointed at the old box:

| Where | Result |
|---|---|
| DNS | `plex.n8io.com` → 15.235.114.39 |
| tgl-prod: Gatus | checks `plex.n8io.com` (new box) |
| tgl-prod: Tautulli, Maintainerr | new box plex.direct address |
| tgl-prod: plex-client-check | new box server id; last run passed |
| tgl-prod: n8n | no IP refs (credentials are encrypted, not searchable) |
| nzb2: Seerr | new box plex.direct + machineId |
| nzb2: `plex-notify.sh` | `PLEX_HOST=root@15.235.114.39` (only a `.bak` holds the old IP) |
| new box | no refs outside this repo |
| this repo | `scripts/cutover.sh` (marked historical); `setup/07.tailscale.sh` default hostname changed to `n8flix-new` |

## Final backup

On n8mini at `~/backups/plex-server/final-2026-11-17/` (1.3 GB, mode 600; earlier copy
in `../2026-10-27/`):

- `config.tgz`: root crontab, `/etc/cron*`, fstab, plexupdate.conf, custom systemd units,
  `.rclone.conf`, `/encfs.xml`, `/plex-server`, `/opt/plex-scan-ui` (no node/),
  authorized_keys, `/root/scripts`, `/plexpy`, `Preferences.xml`.
- `plex-db-2026-11-04.tgz`: final `library.db` + `blobs.db` (last written 2026-11-04).
- `MANIFEST.txt`, `plex-db-files.sha256`: sha256 sums, verified against the old box.

## Teardown

1. `tailscale logout` on the old box; node deleted in the Tailscale admin.
2. Old host key/aliases removed from known_hosts / ssh config on n8mini, nzb2, tgl-prod.
3. Server cancelled in the OVH Canada manager (irreversible; disks are wiped by OVH).

If anything Plex-related ever breaks with a reference to `158.69.124.112`, it is a stale
config: point it at `plex.n8io.com` / the new box.
