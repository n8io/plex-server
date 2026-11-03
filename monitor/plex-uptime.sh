#!/bin/bash
# Runs off-box every 5 minutes (launchd). Checks that Plex answers from the
# internet and that the media mounts are readable, and sends a Slack DM only
# when that changes (down, then recovered), never a stream of repeats.
#
# Config: ~/.config/plex-watch.env (same as plex-watch.sh); PLEX_EXPECTED=0
# silences the Plex check while it's intentionally off.
set -u
CONFIG="${PLEX_WATCH_CONFIG:-$HOME/.config/plex-watch.env}"
# shellcheck source=/dev/null
. "$CONFIG"
STATE="${HOME}/.cache/plex-uptime.state"
mkdir -p "$(dirname "$STATE")"
HOST_IP="${PLEX_HOST#*@}"

notify() {
  /usr/bin/python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1]}))' "$1" |
    curl -fsS -X POST -H 'Content-Type: application/json' --data @- "$SLACK_WEBHOOK_URL" >/dev/null
}

PROBLEMS=()
if [ "${PLEX_EXPECTED:-1}" = "1" ] && ! curl -fsS --max-time 15 "http://${HOST_IP}:32400/identity" >/dev/null 2>&1; then
  # One retry so a single dropped packet doesn't page anyone.
  sleep 20
  curl -fsS --max-time 15 "http://${HOST_IP}:32400/identity" >/dev/null 2>&1 || PROBLEMS+=("Plex isn't reachable from the internet on port 32400")
fi
MOUNTS="$(ssh -o BatchMode=yes -o ConnectTimeout=15 "$PLEX_HOST" \
  'for d in /mnt/x/decrypted /photos/Workouts; do [ -n "$(timeout 15 find "$d" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ] || echo "$d"; done' 2>/dev/null)" \
  || MOUNTS="(couldn't SSH in)"
[ -n "$MOUNTS" ] && PROBLEMS+=("not readable: $(echo $MOUNTS)")

NOW_STATE="ok"; [ ${#PROBLEMS[@]} -gt 0 ] && NOW_STATE="$(printf '%s; ' "${PROBLEMS[@]}")"
LAST_STATE="$(cat "$STATE" 2>/dev/null || echo ok)"
if [ "$NOW_STATE" != "$LAST_STATE" ]; then
  if [ "$NOW_STATE" = "ok" ]; then
    notify ":white_check_mark: Plex server is back to normal."
  else
    notify ":rotating_light: Plex server problem: ${NOW_STATE%; }"
  fi
  echo "$NOW_STATE" > "$STATE"
fi
exit 0
