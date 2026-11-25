#!/bin/bash
# Runs off-box nightly (launchd): copy the newest Plex backup from the server
# and keep the last 14 here. A failure sends one alert with the real reason.
#
# Config: ~/.config/plex-watch.env; PLEX_BACKUP_LOCAL (default ~/backups/plex-server/nightly)
set -u
. "$(cd "$(dirname "$0")" && pwd)/common.sh"
DEST="${PLEX_BACKUP_LOCAL:-$HOME/backups/plex-server/nightly}"
KEEP="${PLEX_BACKUP_LOCAL_KEEP:-14}"
mkdir -p "$DEST"; chmod 700 "$DEST"
[ "${PLEX_EXPECTED:-1}" = "1" ] || exit 0

# Retry for ~10 min so a short network drop isn't an alert.
for TRY in 1 2 3; do
  if LATEST="$(plex_ssh 'ls -1t /var/backups/plex/plex-*.tar.zst 2>/dev/null | head -1' 2>&1)"; then
    SSH_OK=1; break
  fi
  SSH_OK=0; [ "$TRY" -lt 3 ] && sleep 300
done
if [ "$SSH_OK" = "0" ]; then
  notify "⚠️ Plex backup not copied" "The monitor on $(hostname -s) couldn't SSH in: $(echo "$LATEST" | tail -1 | cut -c1-150)"
  exit 0
fi
if [ -z "$LATEST" ]; then
  notify "⚠️ Plex backup missing" "No backup in /var/backups/plex on the server (check plex-backup.timer there)."
  exit 0
fi
NAME="$(basename "$LATEST")"
if [ ! -s "$DEST/$NAME" ]; then
  if ! ERR="$(plex_scp "$PLEX_HOST:$LATEST" "$DEST/$NAME.part" 2>&1)"; then
    rm -f "$DEST/$NAME.part"
    notify "⚠️ Plex backup not copied" "Couldn't copy $NAME off the server: $(echo "$ERR" | tail -1 | cut -c1-150)"
    exit 0
  fi
  mv "$DEST/$NAME.part" "$DEST/$NAME"; chmod 600 "$DEST/$NAME"
fi
ls -1t "$DEST"/plex-*.tar.zst | tail -n +$((KEEP + 1)) | xargs rm -f 2>/dev/null
exit 0
