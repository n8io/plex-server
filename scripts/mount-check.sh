#!/bin/bash
# Watchdog for a mount that is still running but no longer answers (systemd
# already restarts one that dies). Cron runs this every 5 minutes.
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

LOG_FILE="${PLEX_CODE_DIR}/logs/mount-check.log"
PHOTOS_DIR_LOCAL="${PHOTOS_DIR_LOCAL:-/photos/Workouts}"

# A mounted tree has at least one entry; a hung FUSE mount times out.
is_readable() {
  [ -n "$(timeout 30 find "$1" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]
}

check() {
  NAME="$1"; DIR="$2"
  if is_readable "$DIR"; then
    log_info "${NAME}: mounted, OK." "$LOG_FILE"
    return
  fi

  log_error "${NAME}: ${DIR} is not readable. Restarting..." "$LOG_FILE"
  "${PLEX_CODE_DIR}/scripts/cycle-mount.sh" "$NAME"
  sleep 15

  if is_readable "$DIR"; then
    log_info "${NAME}: remounted, back to normal." "$LOG_FILE"
  else
    log_fatal "${NAME}: could not be remounted!" "$LOG_FILE"
  fi
}

check media "$DEC_DIR_LOCAL"
check photos "$PHOTOS_DIR_LOCAL"
