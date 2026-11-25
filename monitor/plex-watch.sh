#!/bin/bash
# Runs off-box (on n8mini, via launchd) once a day. Reads scripts/update-status.sh
# on the Plex server over SSH and pushes an alert only when something needs
# attention. Silence means the server is up to date.
#
# Config: ~/.config/plex-watch.env (see common.sh and docs/monitor.md)
set -u
. "$(cd "$(dirname "$0")" && pwd)/common.sh"
PLEX_CODE_DIR="${PLEX_CODE_DIR:-/plex-server}"
export PLEX_EXPECTED="${PLEX_EXPECTED:-1}"   # 0 while Plex is intentionally off (before a cutover)

STATUS="$(plex_ssh "${PLEX_CODE_DIR}/scripts/update-status.sh" 2>&1)" || {
  sleep 120
  STATUS="$(plex_ssh "${PLEX_CODE_DIR}/scripts/update-status.sh" 2>&1)"
} || {
  notify "⚠️ Plex daily check" "The monitor on $(hostname -s) couldn't SSH in: ${STATUS:0:200}"
  exit 0
}

PROBLEMS="$(/usr/bin/python3 "$(dirname "$0")/plex-watch-check.py" "$STATUS")" || { notify "⚠️ Plex daily check" "Couldn't read the server's status: ${STATUS:0:200}"; exit 0; }

[ -n "$PROBLEMS" ] && notify "⚠️ Plex server needs a look" "${PROBLEMS}"
exit 0
