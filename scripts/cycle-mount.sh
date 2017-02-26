#!/bin/sh
. "../.env"

AWK_BIN="/usr/bin/awk"
CUT_BIN="/usr/bin/cut"
DATE_BIN="/bin/date"
ENV_BIN="/usr/bin/env"
GREP_BIN="/bin/grep"
KILL_BIN="/bin/kill"
MKDIR_BIN="/bin/mkdir"
SCREEN_BIN="/usr/bin/screen"
TEE_BIN="/usr/bin/tee"
XARGS_BIN="/usr/bin/xargs"

"$ENV_BIN" | "$GREP_BIN" ENC | "$TEE_BIN" -a "/plex-server/logs/rclone-mount.log"

DEF_PLEX_CODE_DIR="$([ ! -z "$PLEX_CODE_DIR" ] && echo "$PLEX_CODE_DIR" || echo "/plex-server")"
DEF_LOGS_DIR="$([ ! -z "$PLEX_CODE_DIR" ] && echo "${PLEX_CODE_DIR}/logs" || echo "${DEF_PLEX_CODE_DIR}/logs")"
DEF_LOG_FILE="rclone-mount.log"

PLEX_CODE_DIR="${1:-$DEF_PLEX_CODE_DIR}"
LOGS_DIR="${2:-$DEF_LOGS_DIR}"
LOG_FILE="${LOGS_DIR}/${3:-$DEF_LOG_FILE}"

"$MKDIR_BIN" -p "$LOGS_DIR"

"$DATE_BIN" > "$LOG_FILE"

echo -n "Killing last screen session..." | "$TEE_BIN" -a "$LOG_FILE"
"$SCREEN_BIN" -ls | "$GREP_BIN" ".rclone-mount" | "$CUT_BIN" -d. -f1 | "$AWK_BIN" '{print $1}' | "$XARGS_BIN" "$KILL_BIN" 2>/dev/null || true
echo "done." | "$TEE_BIN" -a "$LOG_FILE"

echo -n "Starting up new screen session..." | "$TEE_BIN" -a "$LOG_FILE"
"$SCREEN_BIN" -S rclone-mount -dm "${PLEX_CODE_DIR}/scripts/mount.sh" | "$TEE_BIN" -a "$LOG_FILE"
echo "done." | "$TEE_BIN" -a "$LOG_FILE"
