# plex-sharing-audit: quarterly account-sharing report

Emails Nate a report of Plex accounts that look shared with another household.
**Read-only**: it never changes Plex, Tautulli or any user.

Runs on the Plex box at 14:00 UTC (9 AM ET) on the 1st of January, April, July and October (`/etc/cron.d/plex-sharing-audit`).
Install / update: `cd /plex-server && git pull && ./addons/plex-sharing-audit.sh`.
Run now: `/usr/local/sbin/plex-sharing-audit.py` (emails) or `--no-email` (prints).
Config: `/etc/plex-sharing-audit.env` (see `plex-sharing-audit.env.example`). Log: `/var/log/plex-sharing-audit.log`.
Reports are kept in `/var/lib/plex-sharing-audit/report-YYYY-MM-DD.{txt,html}` (root only, they contain IPs).
If a run fails it sends a Pushbullet push with the reason.

## Data

- **Plays**: Tautulli `get_history` (`grouping=0`, last `LOOKBACK_DAYS` = 180) from the Coolify Tautulli at
  plex-stats.n8io.com, which has the full history with client IPs. Plex's own DB has no IPs.
- **IP lookups**: DB-IP lite city and ASN databases (free, CC BY 4.0), downloaded monthly into `/var/lib/plex-sharing-audit`.
  Lookups are local; IPs are never sent to a web API. db-ip.com returns 403 to Python's default User-Agent.
- **Email**: Resend API, from `n8flix-noreply@n8io.com` (same verified domain as Seerr's emails).

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
