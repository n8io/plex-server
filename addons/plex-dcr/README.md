# plex-dcr: weekly deletion-candidate rating

Scores every movie and show 0-100 (DCR, higher means a better candidate to delete) and keeps
Plex Janitor (Maintainerr) **Leaving soon** collections, one per Plex library (`LEAVING_SOON_COLLECTIONS`),
filled with every title scoring `MIN_DCR` (64) or more. `TARGET_TB` can cap the list size; 0 (the default) means no cap. A size target would refill the list every week after approved deletions, so the default is a fixed score bar. Users see those collections in Plex.
A title drops out on the next run once someone plays it or adds it to a watchlist.

**It never deletes anything.** Each Monday it pushes a Pushbullet summary. Titles that have
sat in Leaving soon for `GRACE_DAYS` are listed for approval. Only titles Nate approves are
deleted, one by one, with `rclone deletefile` on the encrypted Drive path, and are unmonitored
in Radarr/Sonarr.

Install / update: `./addons/plex-dcr.sh` (Mondays 14:00 UTC via `/etc/cron.d/plex-dcr`).
Config: `/etc/plex-dcr.env` (see `plex-dcr.env.example`). It starts with `DRY_RUN=1`.
Log: `/var/log/plex-dcr.log`. Output: `/var/lib/plex-dcr/report.json` (every scored title).

## Score (100 points)

| Part | Points | How |
| --- | --- | --- |
| Audience | 35 | Distinct Plex accounts that ever played it: 0 = 35, 1 = 28, 2 = 18, 3 = 10, 4-5 = 5, 6+ = 0 |
| Time since last play | 20 | 0 if played in the last 90 days, rising to 20 at 3 years. Never played: counted from the add date |
| Unpopularity | 25 | IMDb votes (15) and rating (10) as a percentile within the library, movies and shows separately |
| Depth | 10 | Movies by total plays (0 = 10, 1 = 7, 2 = 4, 3-4 = 2, 5+ = 0). Shows by share of episodes ever played (0% = 10, 0 at 50%) |
| Size | 10 | Percentile of size among all titles |

Not scored: `EXCLUDE_SECTIONS` (Workouts by default), anything added in the last 90 days, items with no files (0 bytes) and orphaned items outside any library.

## Data

- Plex DB: a `Plex SQLite .backup` copy under `/var/lib/plex-dcr`, read and then deleted.
  `metadata_item_views` holds every play by every account (back to Jan 2022 on this server).
- IMDb: `datasets.imdbws.com/title.ratings.tsv.gz`, cached for 6 days.
- Watchlists: Seerr `GET /api/v1/user/{id}/watchlist` for every Seerr user (admin API key).
  Users whose Plex sign-in in Seerr went stale come back empty.

## Plex Janitor

Maintainerr's API has no auth of its own; the basic auth on plex-janitor.n8io.com is the only
gate. The collections must be manual-only rule groups with **Do nothing** (`arrAction` 4)
and names that do **not** start with "Movies" or "TV Shows", so the n8n
"Plex | Delete Unwatched Media" workflow (paused 2026-11-15) can never pick them up.
Titles are added with `POST /api/collections/add` (`manual: true`) and removed with
`POST /api/collections/remove`.

Created 2026-11-15: rule groups / collections 6 "Leaving Soon: Movies" (library 2),
7 "Leaving Soon: TV Shows" (1), 8 "Leaving Soon: Kid Shows" (4), 9 "Leaving Soon: Prerelease" (7),
all `useRules: false`, `arrAction` 4, no delete timer. The old "Haven't Watched In Forever" groups
4 and 5 were deactivated. Gotcha: `PUT /api/rules` resets `collection.arrAction` to 0 (Delete)
unless you send it back in the body, so always send the full collection block.
