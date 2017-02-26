#!/bin/bash
set -e
SCRIPT=$(realpath $0)
PLEX_CODE_DIR=$(dirname $(dirname $SCRIPT))
echo "Loading .env at: "${PLEX_CODE_DIR}/.env"" | tee -a "/plex-server/logs/mount-check.log"
. "${PLEX_CODE_DIR}/.env"

FIND_BIN="/usr/bin/find"
SLEEP_BIN="/bin/sleep"
TEE_BIN="/usr/bin/tee"
LOG_FILE="${PLEX_CODE_DIR}/logs/mount-check.log"
COUNT=$("$FIND_BIN" "${DEC_DIR_LOCAL}" -maxdepth 1 -type d | wc -l)

if [ "$COUNT" -eq "1" ]; then
  echo "$(date) ERROR: Drives are not mounted. Attempting to remount..." | "$TEE_BIN" -a "$LOG_FILE"
  "${PLEX_CODE_DIR}/scripts/cycle-mount.sh"
  "$SLEEP_BIN" 2

  RECOUNT=$("$FIND_BIN" "${DEC_DIR_LOCAL}" -maxdepth 1 -type d | wc -l)

  if [ "$RECOUNT" -eq "1" ]; then
    echo "$(date) FATAL: Drives could not be remounted. Check the logs!" | "$TEE_BIN" -a "$LOG_FILE"
  else
    echo "$(date)  INFO: Drives mounted successfully. Everything is back to normal." | "$TEE_BIN" -a "$LOG_FILE"
  fi
else
  echo "$(date)  INFO: Drives are mounted. Everything is OK." | "$TEE_BIN" -a "$LOG_FILE"
fi

set +e
