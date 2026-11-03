#!/bin/bash
# Print how many streams Plex is serving right now (0 if Plex is down).
# Used to make sure updates and reboots never interrupt anyone.
PLEX_URL="${PLEX_URL:-http://127.0.0.1:32400}"
PLEX_PREFS="${PLEX_APP_SUPPORT_DIR:-/var/lib/plexmediaserver/Library/Application Support}/Plex Media Server/Preferences.xml"
PLEX_TOKEN="${PLEX_TOKEN:-$(grep -oE 'PlexOnlineToken="[^"]+"' "$PLEX_PREFS" 2>/dev/null | cut -d'"' -f2)}"

XML="$(curl -fsS --max-time 10 -H "X-Plex-Token: ${PLEX_TOKEN}" "${PLEX_URL}/status/sessions" 2>/dev/null)" || { echo 0; exit 0; }
echo "$XML" | grep -oE '<MediaContainer[^>]* size="[0-9]+"' | grep -oE '[0-9]+"$' | tr -d '"' | head -n 1
