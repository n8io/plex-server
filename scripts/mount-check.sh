#!/bin/bash
set -e
PLEX_CODE_DIR=$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
. "${PLEX_CODE_DIR}/.env"

TEE_BIN="/usr/bin/tee"
LOG_FILE="${PLEX_CODE_DIR}/logs/mount-check.log"
COUNT=$(find "${DEC_DIR_LOCAL}" -maxdepth 1 -type d | wc -l)
COUNT=$((COUNT+1-1))

if [ $COUNT -eq 0 ]; then
  echo "$(date) CRITICAL: Drives are not mounted. Need to remount!" | "$TEE_BIN" -a "$LOG_FILE"
  "${PLEX_CODE_DIR}/scripts/cycle-mount.sh"
else
  echo "$(date)     INFO: Drives are mounted. Everything is OK." | "$TEE_BIN" -a "$LOG_FILE"
fi

set +e
