#!/bin/sh
SCREEN_BIN="/usr/bin/screen"
DEF_PLEX_CODE_DIR="$([ ! -z "$PLEX_CODE_DIR" ] && echo "$PLEX_CODE_DIR" || echo "/plex-server/scripts")"
DEF_LOGS_DIR="$([ ! -z "$PLEX_CODE_DIR" ] && echo "${PLEX_CODE_DIR}/logs" || echo "/plex-server/logs")"
DEF_LOG_FILE="rclone-mount.log"

PLEX_CODE_DIR="${1:-$DEF_PLEX_CODE_DIR}"
LOGS_DIR="${1:-$DEF_LOGS_DIR}"
LOG_FILE="${LOGS_DIR}/${3:-$DEF_LOG_FILE}"

mkdir -p "$LOGS_DIR"

echo "
SCREEN_BIN=$SCREEN_BIN
PLEX_CODE_DIR=$PLEX_CODE_DIR
LOG_FILE=$LOG_FILE
" > "$LOG_FILE"

echo "Unmounting..." >> "$LOG_FILE"
"$SCREEN_BIN" -ls | grep ".rclone-mount" | cut -d. -f1 | awk '{print $1}' | xargs kill 2>/dev/null || true

echo "Mounting..." >> "$LOG_FILE"
"$SCREEN_BIN" -S rclone-mount -dm "${PLEX_CODE_DIR}/scripts/mount.sh"
