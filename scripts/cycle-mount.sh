#!/bin/sh
SCREEN_BIN="/usr/bin/screen"
DEF_PLEX_CODE_DIR="$([ ! -z "$PLEX_CODE_DIR" ] && echo "$PLEX_CODE_DIR" || echo "/plex-server")"
DEF_LOGS_DIR="$([ ! -z "$PLEX_CODE_DIR" ] && echo "${PLEX_CODE_DIR}/logs" || echo "${DEF_PLEX_CODE_DIR}/logs")"
DEF_LOG_FILE="rclone-mount.log"

PLEX_CODE_DIR="${1:-$DEF_PLEX_CODE_DIR}"
LOGS_DIR="${2:-$DEF_LOGS_DIR}"
LOG_FILE="${LOGS_DIR}/${3:-$DEF_LOG_FILE}"

mkdir -p "$LOGS_DIR"

echo "$(date)" > "$LOG_FILE"

echo -n "Killing last screen session..." | tee -a "$LOG_FILE"
"$SCREEN_BIN" -ls | grep ".rclone-mount" | cut -d. -f1 | awk '{print $1}' | xargs kill 2>/dev/null || true
echo "done." | tee -a "$LOG_FILE"

echo -n "Starting up new screen session..." | tee -a "$LOG_FILE"
"$SCREEN_BIN" -S rclone-mount -dm "${PLEX_CODE_DIR}/scripts/mount.sh" | tee -a "$LOG_FILE"
echo "done." | tee -a "$LOG_FILE"
