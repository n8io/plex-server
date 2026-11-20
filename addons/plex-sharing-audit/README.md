# plex-sharing-audit: quarterly account-sharing report

Finds Plex accounts that look shared with another household. **Read-only**: it never changes Plex, Tautulli or any user.

**Schedule (Nate, 2026-11-20): reminder only.** At 14:00 UTC (9 AM ET) on the 1st of Jan, Apr, Jul and Oct the Plex box
sends a Pushbullet push ("Plex sharing audit is due") linking to the Claude project thread "Detect Plex account sharing".
Nate opens it and asks Claude to run the audit; Claude follows the runbook below and replies in the thread.
Install / update the reminder: `cd /plex-server && git pull && ./addons/plex-sharing-audit.sh`
(cron `/etc/cron.d/plex-sharing-audit`, config `/etc/plex-sharing-audit.env`, Pushbullet token copied from `/etc/plex-trash-clean.env`).

## Runbook (for Claude)

Read-only on the VPS. n8mini's auto-mode blocks `ssh tgl-prod` until Nate types a go-ahead in the thread; ask for it
in a copy-pasteable code block, e.g. `yes, ssh to tgl-prod read-only and export the Tautulli DB for the sharing audit`.

1. Take a consistent copy of the Coolify Tautulli DB without touching the live file (run from n8mini):
   ```
   C=$(ssh tgl-prod "docker ps --format '{{.Names}}' | grep -m1 tautulli")
   ssh tgl-prod "docker exec $C python3 -c \"import sqlite3;s=sqlite3.connect('file:/config/tautulli.db?mode=ro',uri=True);d=sqlite3.connect('/tmp/taut-audit.db');s.backup(d)\""
   ssh tgl-prod "docker exec $C cat /tmp/taut-audit.db" > /tmp/taut-audit.db
   ssh tgl-prod "docker exec $C rm -f /tmp/taut-audit.db"
   ```
2. Run the audit on that copy (needs `pip install maxminddb`; it downloads the DB-IP lite databases itself):
   `STATE_DIR=~/plex-sharing-audit ENV_FILE=/dev/null python3 addons/plex-sharing-audit/plex-sharing-audit.py --from-db /tmp/taut-audit.db --no-email`
3. Delete `/tmp/taut-audit.db`. Summarize the report for Nate in the thread (flagged accounts with evidence, then the cleared ones).
   The full report is in `$STATE_DIR/report-YYYY-MM-DD.txt` (it contains IPs: keep it on n8mini, never in a repo).

Other inputs: `--from-csv sessions.csv` (the 2026-11-18 export format) or, with `TAUTULLI_API_KEY`, the Tautulli API.
Add `RESEND_API_KEY`/`EMAIL_TO` and drop `--no-email` to email the report instead.

## Data

- **Plays**: the Coolify Tautulli at plex-stats.n8io.com (`session_history`, last `LOOKBACK_DAYS` = 180), which has the
  full history with client IPs. Plex's own DB has no IPs.
- **IP lookups**: DB-IP lite city and ASN databases (free, CC BY 4.0), downloaded monthly into `/var/lib/plex-sharing-audit`.
  Lookups are local; IPs are never sent to a web API. db-ip.com returns 403 to Python's default User-Agent.

## Method

Agreed with Nate on 2026-11-18 (project thread "Detect Plex account sharing"): watching on a phone over cellular is normal.

1. Each IP is classed as **mobile** (Verizon Wireless, T-Mobile, AT&T Mobility ranges), **vpn** (Cloudflare/WARP,
   iCloud Private Relay, VPN and cloud providers) or **home**. Mobile and VPN plays never flag anyone.
2. A home network is an IPv4 address or an IPv6 /56. Networks are merged into one **home** when the same TV-type
   device (anything but Plex for iOS, Android (Mobile), Web, Windows or Mac) plays on both. ISP IP changes,
   IPv4/IPv6 pairs and house moves become one home, because the Roku or Fire TV stick moves with the people.
3. A **real home** has a TV-type device, at least `MIN_HOME_PLAYS` (10) plays and activity over more than `TRIP_DAYS` (14).
   Anything smaller is a **trip** (vacation rental, hotel, relatives).
4. **Flagged** when any of these is true:
   - two real homes were both active over at least `OVERLAP_DAYS` (14) of the same days,
   - one home (merged by a carried device) has two ISP/state locations both busy over the same 14+ days,
   - `CONCURRENT_MIN` (3) or more streams ran at the same moment from two different home connections.
5. **Notes** (not flagged): moves (same TV device at a new ISP/state, no overlap) and trips.

First run (by hand, 2026-11-18, 180 days, 5,065 plays): one account flagged (two Spectrum homes in Lorain/Cuyahoga
counties streaming at the same time May to Aug 2026). Moves and trips for 4 other users were cleared. The script reproduces that result.

## Limits

- Two households on the same ISP **and** linked by a stick that was carried between them, but never busy in the
  same weeks, look like a move.
- A home on fixed-wireless from a cellular carrier (e.g. Verizon 5G Home on AS6167) counts as mobile and is never flagged.
