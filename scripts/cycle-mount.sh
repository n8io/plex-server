#!/bin/sh
set -e

DEF_PLEX_CODE_DIR="$([ ! -z "$PLEX_CODE_DIR" ] && echo "$PLEX_CODE_DIR" || echo "/root/plex-server/scripts")"
DEF_LOGS_DIR="$([ ! -z "$PLEX_CODE_DIR" ] && echo "${PLEX_CODE_DIR}/logs" || echo "/root/plex-server/logs")"
DEF_LOG_FILE="rclone-mount.log"

PLEX_CODE_DIR="${1:-$DEF_PLEX_CODE_DIR}"
LOGS_DIR="${1:-$DEF_LOGS_DIR}"
LOG_FILE="${LOGS_DIR}/${3:-$DEF_LOG_FILE}"

mkdir -p "$LOGS_DIR"

echo "Unmounting..." > "$LOG_FILE"
screen -ls | grep ".rclone-mount" | cut -d. -f1 | awk '{print $1}' | xargs kill 2>/dev/null || true

echo "Mounting..." >> "$LOG_FILE"
screen -S rclone-mount -dm "${PLEX_CODE_DIR}/mount.sh"
