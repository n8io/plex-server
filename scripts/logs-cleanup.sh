#!/bin/bash
DIR="$(dirname $0)"
PLEX_CODE_DIR=$(dirname "$DIR")
. "${PLEX_CODE_DIR}/.env"

empty_log_file() {
  FILE="${PLEX_CODE_DIR:?Not set!}/logs/${1:?Not set!}"
  rm -rf "$FILE"
  touch "$FILE"
}

empty_log_file "rclone-mount.log"
empty_log_file "mount-check.log"
