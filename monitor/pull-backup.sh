#!/bin/bash
# Runs off-box nightly (launchd): copy the newest Plex backup from the server
# and keep the last 14 here. A failure DMs on Slack.
#
# Config: ~/.config/plex-watch.env; PLEX_BACKUP_LOCAL (default ~/backups/plex-server/nightly)
set -u
CONFIG="${PLEX_WATCH_CONFIG:-$HOME/.config/plex-watch.env}"
# shellcheck source=/dev/null
. "$CONFIG"
DEST="${PLEX_BACKUP_LOCAL:-$HOME/backups/plex-server/nightly}"
KEEP="${PLEX_BACKUP_LOCAL_KEEP:-14}"
mkdir -p "$DEST"; chmod 700 "$DEST"

notify() {
  /usr/bin/python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1]}))' "$1" |
    curl -fsS -X POST -H 'Content-Type: application/json' --data @- "$SLACK_WEBHOOK_URL" >/dev/null
}

[ "${PLEX_EXPECTED:-1}" = "1" ] || exit 0

LATEST="$(ssh -o BatchMode=yes -o ConnectTimeout=20 "$PLEX_HOST" 'ls -1t /var/backups/plex/plex-*.tar.zst 2>/dev/null | head -1')"
if [ -z "$LATEST" ]; then
  notify ":warning: Plex backup: no backup found on the server to copy."
  exit 0
fi
NAME="$(basename "$LATEST")"
if [ ! -s "$DEST/$NAME" ]; then
  if ! scp -q -o BatchMode=yes "$PLEX_HOST:$LATEST" "$DEST/$NAME.part"; then
    rm -f "$DEST/$NAME.part"
    notify ":warning: Plex backup: couldn't copy $NAME off the server."
    exit 0
  fi
  mv "$DEST/$NAME.part" "$DEST/$NAME"; chmod 600 "$DEST/$NAME"
fi
ls -1t "$DEST"/plex-*.tar.zst | tail -n +$((KEEP + 1)) | xargs rm -f 2>/dev/null
exit 0
