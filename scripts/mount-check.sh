#!/bin/bash
set -e
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

FIND_BIN="/usr/bin/find"
SLEEP_BIN="/bin/sleep"
LOG_FILE="${PLEX_CODE_DIR}/logs/mount-check.log"
COUNT=$("$FIND_BIN" "${DEC_DIR_LOCAL}" -maxdepth 1 -type d | wc -l)

if [ "$COUNT" -eq "1" ]; then
  log_error "Drives are not mounted. Attempting to remount..." "$LOG_FILE"
  "${PLEX_CODE_DIR}/scripts/cycle-mount.sh"
  "$SLEEP_BIN" 2

  RECOUNT=$("$FIND_BIN" "$DEC_DIR_LOCAL" -maxdepth 1 -type d | wc -l)

  if [ "$RECOUNT" -eq "1" ]; then
    log_fatal "Drives could not be remounted. Check the logs!" "$LOG_FILE"
  else
    log_info "Drives mounted successfully. Everything is back to normal." "$LOG_FILE"
  fi
else
  log_info "Drives are mounted. Everything is OK." "$LOG_FILE"
fi

set +e
