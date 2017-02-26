#!/bin/sh
DIR="$(dirname $0)"
PLEX_CODE_DIR=$(dirname "$DIR")
. "${PLEX_CODE_DIR}/.env"

AWK_BIN="/usr/bin/awk"
CUT_BIN="/usr/bin/cut"
DATE_BIN="/bin/date"
GREP_BIN="/bin/grep"
KILL_BIN="/bin/kill"
SCREEN_BIN="/usr/bin/screen"
TEE_BIN="/usr/bin/tee"
XARGS_BIN="/usr/bin/xargs"

DEF_PLEX_CODE_DIR="$([ ! -z "$PLEX_CODE_DIR" ] && echo "$PLEX_CODE_DIR" || echo "/plex-server")"
DEF_LOGS_DIR="$([ ! -z "$PLEX_CODE_DIR" ] && echo "${PLEX_CODE_DIR}/logs" || echo "${DEF_PLEX_CODE_DIR}/logs")"
DEF_LOG_FILE="rclone-mount.log"

PLEX_CODE_DIR="${1:-$DEF_PLEX_CODE_DIR}"
LOGS_DIR="${2:-$DEF_LOGS_DIR}"
LOG_FILE="${LOGS_DIR}/${3:-$DEF_LOG_FILE}"

"$DATE_BIN" > "$LOG_FILE"

echo -n "Killing last screen session..." | "$TEE_BIN" -a "$LOG_FILE"
"$SCREEN_BIN" -ls | "$GREP_BIN" ".rclone-mount" | "$CUT_BIN" -d. -f1 | "$AWK_BIN" '{print $1}' | "$XARGS_BIN" "$KILL_BIN" 2>/dev/null || true
echo "done." | "$TEE_BIN" -a "$LOG_FILE"

echo -n "Starting up new screen session..." | "$TEE_BIN" -a "$LOG_FILE"
"$SCREEN_BIN" -S rclone-mount -dm "${PLEX_CODE_DIR}/scripts/mount.sh" | "$TEE_BIN" -a "$LOG_FILE"
echo "done." | "$TEE_BIN" -a "$LOG_FILE"
