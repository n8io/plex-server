#!/bin/bash
# Partial Plex library scan for a single show/movie (or any folder) — no full library scan.
#
#   plex-scan.sh -t alone                      fuzzy-match a TV show and scan just its folder
#   plex-scan.sh -m "super mario"              fuzzy-match a movie
#   plex-scan.sh game changer                  search TV and movies (unquoted words are joined)
#   plex-scan.sh -f -t alone                   also force a metadata refresh of existing items
#   plex-scan.sh "tv/adult/Alone/Season 13"    an explicit path (relative to $DEC_DIR_LOCAL or absolute)
#   plex-scan.sh -l -t gold                    just list the matches
#
# Options: -t/--tv  -m/--movie  -f/--force  -y/--first (auto-pick best match)  -l/--list  -n/--dry-run
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

PLEX_URL="${PLEX_URL:-http://localhost:32400}"
PLEX_APP_SUPPORT_DIR="${PLEX_APP_SUPPORT_DIR:-/var/lib/plexmediaserver/Library/Application Support}"
PLEX_PREFS="${PLEX_APP_SUPPORT_DIR}/Plex Media Server/Preferences.xml"

# Server token: read at runtime from Plex's own prefs, never printed or stored.
if [ -z "$PLEX_TOKEN" ]; then
  PLEX_TOKEN="$(grep -oE 'PlexOnlineToken="[^"]+"' "$PLEX_PREFS" 2>/dev/null | cut -d'"' -f2)"
fi
if [ -z "$PLEX_TOKEN" ]; then
  echo "plex-scan: no Plex token found in ${PLEX_PREFS} (set PLEX_TOKEN to override)" >&2
  exit 1
fi

export PLEX_URL PLEX_TOKEN DEC_DIR_LOCAL
exec python3 "${PLEX_CODE_DIR}/scripts/plex-scan.py" "$@"
