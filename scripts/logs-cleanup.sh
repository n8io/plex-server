#!/bin/bash
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

# Truncate in place rather than rm+touch so open file handles (rclone's
# --log-file, tee) keep writing to the same inode.
empty_log_file() {
  FILE="${PLEX_CODE_DIR:?Not set!}/logs/${1:?Not set!}"
  : > "$FILE"
}

empty_log_file "rclone-mount.log"
empty_log_file "rclone-mount-debug.log"
empty_log_file "mount-check.log"
empty_log_file "plexupdate-cron.log"
