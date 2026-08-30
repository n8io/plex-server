#!/bin/bash
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

FUSERMOUNT_BIN="/bin/fusermount"
TEE_BIN="/usr/bin/tee"

# cron runs with PATH=/usr/bin:/bin; rclone execs `fusermount3` via PATH.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Requires rclone >= 1.60 (VFS full cache). rclone >= 1.60 also expects a
# `fusermount3` binary; on FUSE 2-only hosts symlink it to /bin/fusermount.
DEF_RCLONE_BIN="$([ ! -z "$RCLONE_BIN" ] && echo "$RCLONE_BIN" || echo "/usr/sbin/rclone")"
DEF_RCLONE_CONFIG="$([ ! -z "$RCLONE_CONFIG" ] && echo "$RCLONE_CONFIG" || echo "/root/.rclone.conf")"
DEF_RCLONE_REMOTE_NAME="$([ ! -z "$RCLONE_REMOTE_NAME" ] && echo "$RCLONE_REMOTE_NAME" || "$DEF_RCLONE_BIN" --config "$DEF_RCLONE_CONFIG" listremotes | head -n 1 | sed -e 's/\(:\)*$//g')"
DEF_ENC_DIR_REMOTE="$([ ! -z "$ENC_DIR_REMOTE" ] && echo "$ENC_DIR_REMOTE" || echo "/encrypted")"
DEF_ENC_DIR_LOCAL="$([ ! -z "$ENC_DIR_LOCAL" ] && echo "$ENC_DIR_LOCAL" || echo "/mnt/x/encrypted")"
DEF_LOG_DIR="$([ ! -z "$LOG_DIR" ] && echo "$LOG_DIR" || echo "${PLEX_CODE_DIR}/logs")"
DEF_LOG_FILE="$([ ! -z "$LOG_FILE" ] && echo "$LOG_FILE" || echo "rclone-mount.log")"
# Local disk cache for media read through the mount. Anything played once is
# served from here (LRU, capped by RCLONE_CACHE_MAX_SIZE) instead of the cloud.
DEF_CACHE_DIR="$([ ! -z "$RCLONE_CACHE_DIR" ] && echo "$RCLONE_CACHE_DIR" || echo "/home/rclone-cache")"
DEF_CACHE_MAX_SIZE="$([ ! -z "$RCLONE_CACHE_MAX_SIZE" ] && echo "$RCLONE_CACHE_MAX_SIZE" || echo "800G")"

RCLONE_BIN="${1:-$DEF_RCLONE_BIN}"
RCLONE_REMOTE_NAME="${2:-$DEF_RCLONE_REMOTE_NAME}"
ENC_DIR_REMOTE="${3:-$DEF_ENC_DIR_REMOTE}"
ENC_DIR_LOCAL="${4:-$DEF_ENC_DIR_LOCAL}"
LOG_DIR="${5:-$DEF_LOG_DIR}"
LOG_FILE="${LOG_DIR}/${6:-$DEF_LOG_FILE}"
CACHE_DIR="${7:-$DEF_CACHE_DIR}"
CACHE_MAX_SIZE="${8:-$DEF_CACHE_MAX_SIZE}"
RCLONE_CONFIG="$DEF_RCLONE_CONFIG"

mkdir -p "$CACHE_DIR"

log_info "Unmounting..." "$LOG_FILE"
"$FUSERMOUNT_BIN" -uz "$ENC_DIR_LOCAL" 2>/dev/null || true

log_info "Mounting with $("$RCLONE_BIN" version | head -n 1) (vfs cache: ${CACHE_DIR}, max ${CACHE_MAX_SIZE})..." "$LOG_FILE"
"$RCLONE_BIN" --config "$RCLONE_CONFIG" mount \
  --read-only \
  --allow-non-empty \
  --allow-other \
  --vfs-cache-mode full \
  --cache-dir "$CACHE_DIR" \
  --vfs-cache-max-size "$CACHE_MAX_SIZE" \
  --vfs-cache-max-age 720h \
  --vfs-read-ahead 512M \
  --vfs-read-chunk-size 64M \
  --vfs-read-chunk-size-limit 2G \
  --buffer-size 32M \
  --dir-cache-time 9999h \
  --poll-interval 1m \
  --vfs-fast-fingerprint \
  --checkers 16 \
  --stats 0 \
  --log-level INFO \
  --log-file "${LOG_DIR}/rclone-mount-debug.log" \
  "${RCLONE_REMOTE_NAME}:${ENC_DIR_REMOTE}/" \
  "$ENC_DIR_LOCAL" | "$TEE_BIN" -a "$LOG_FILE" \
  ;
