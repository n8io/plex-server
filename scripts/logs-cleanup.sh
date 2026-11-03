#!/bin/bash
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

# Truncate in place rather than rm+touch so open file handles (rclone's
# --log-file) keep writing to the same inode.
empty_log_file() {
  FILE="${PLEX_CODE_DIR:?Not set!}/logs/${1:?Not set!}"
  [ -f "$FILE" ] && : > "$FILE"
  return 0
}

empty_log_file "rclone-media.log"
empty_log_file "rclone-photos.log"
empty_log_file "mount-check.log"
