# Plex Scan UI

A small web page to browse **Library → Show → Season → Episode** (or Library → Movie)
and click **Scan** to tell Plex to scan just that folder (recursively) for new or
changed files. No full library scans, no cron.

| You click   | Plex scans                                        |
|-------------|---------------------------------------------------|
| Library     | every folder in the library (= full scan, asks first) |
| Show        | the show folder (finds new seasons/episodes)      |
| Season      | the season folder(s) holding its episodes         |
| Movie/Episode | the folder holding the file                     |
| Folder (via **Folders**) | that folder on disk                   |

"refresh metadata" also re-fetches posters/info for the item.
Paths come straight from Plex, so no Docker path mapping is needed.

## Run (Docker, next to Plex)
1. Copy this folder to the Plex server.
2. Edit `docker-compose.yml`: set `PLEX_URL` to Plex's container name (or
   `http://<host-ip>:32400` if Plex uses host networking) and attach it to Plex's network.
3. Create `.env`:
   ```
   PLEX_USERNAME=...
   PLEX_PASSWORD=...
   UI_USER=nate
   UI_PASS=<something long>
   ```
   (Or `PLEX_TOKEN=...` instead of username/password.)
4. `docker compose up -d --build`, open http://127.0.0.1:8080.

Without Docker: `PLEX_URL=... PLEX_TOKEN=... UI_USER=... UI_PASS=... node server.js` (Node 18+).

## Notes
- New uploads have to be visible on the rclone mount first. With Drive's default
  `--poll-interval 1m` that happens within about a minute. If a scan finds nothing,
  wait a minute or lower `--dir-cache-time`.
- Brand new shows/movies have no Plex item yet. Open the library, click **Folders**,
  and browse the folders on disk (as Plex sees them), then **Scan** the new folder.
  Only paths inside that library are allowed.
- The UI holds a Plex admin token. Keep UI_USER/UI_PASS set and don't expose it
  publicly without HTTPS.
