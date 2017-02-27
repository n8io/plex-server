#!/bin/sh
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

AWK_BIN="/usr/bin/awk"
CUT_BIN="/usr/bin/cut"
GREP_BIN="/bin/grep"
KILL_BIN="/bin/kill"
SCREEN_BIN="/usr/bin/screen"
XARGS_BIN="/usr/bin/xargs"

DEF_PLEX_CODE_DIR="$([ ! -z "$PLEX_CODE_DIR" ] && echo "$PLEX_CODE_DIR" || echo "/plex-server")"
DEF_LOGS_DIR="$([ ! -z "$PLEX_CODE_DIR" ] && echo "${PLEX_CODE_DIR}/logs" || echo "${DEF_PLEX_CODE_DIR}/logs")"
DEF_LOG_FILE="rclone-mount.log"

PLEX_CODE_DIR="${1:-$DEF_PLEX_CODE_DIR}"
LOGS_DIR="${2:-$DEF_LOGS_DIR}"
LOG_FILE="${LOGS_DIR}/${3:-$DEF_LOG_FILE}"

[ -z "$QUIET" ] && log_info "Killing last screen session..." "$LOG_FILE"
"$SCREEN_BIN" -ls | "$GREP_BIN" ".rclone-mount" | "$CUT_BIN" -d. -f1 | "$AWK_BIN" '{print $1}' | "$XARGS_BIN" "$KILL_BIN" 2>/dev/null || true

[ -z "$QUIET" ] && log_info "Starting up new screen session..." "$LOG_FILE"
"$SCREEN_BIN" -S rclone-mount -dm "${PLEX_CODE_DIR}/scripts/mount.sh"
