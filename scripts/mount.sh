#!/bin/bash
DEF_RCLONE_BIN="$([ ! -z "$RCLONE_BIN" ] && echo "$RCLONE_BIN" || which rclone)"
DEF_RCLONE_REMOTE_NAME="$([ ! -z "$RCLONE_REMOTE_NAME" ] && echo "$RCLONE_REMOTE_NAME" || "$RCLONE_BIN" listremotes | head -n 1 | sed -e 's/\(:\)*$//g')"
DEF_ENC_DIR_REMOTE="$([ ! -z "$ENC_DIR_REMOTE" ] && echo "$ENC_DIR_REMOTE" || echo "/encrypted")"
DEF_ENC_DIR_LOCAL="$([ ! -z "$ENC_DIR_LOCAL" ] && echo "$ENC_DIR_LOCAL" || echo "/mnt/x/encrypted")"
DEF_LOG_DIR="$([ ! -z "$LOG_DIR" ] && echo "$LOG_DIR" || echo "${PLEX_CODE_DIR}/logs")"
DEF_LOG_FILE="$([ ! -z "$LOG_FILE" ] && echo "$LOG_FILE" || echo "rclone-mount.log")"

RCLONE_BIN="${1:-$DEF_RCLONE_BIN}"
RCLONE_REMOTE_NAME="${2:-$DEF_RCLONE_REMOTE_NAME}"
ENC_DIR_REMOTE="${3:-$DEF_ENC_DIR_REMOTE}"
ENC_DIR_LOCAL="${4:-$DEF_ENC_DIR_LOCAL}"
LOG_DIR="${5:-$DEF_LOG_DIR}"
LOG_FILE="${LOG_DIR}/${6:-$DEF_LOG_FILE}"

mkdir -p "$LOG_DIR"

echo "Unmounting... " | tee -a "$LOG_FILE"
fusermount -uz "$ENC_DIR_LOCAL" 2>/dev/null || true

echo "$(date)
Mounting with options:
RCLONE_BIN=${RCLONE_BIN}
RCLONE_REMOTE_NAME=${RCLONE_REMOTE_NAME}
ENC_DIR_REMOTE=${ENC_DIR_REMOTE}
ENC_DIR_LOCAL=${ENC_DIR_LOCAL}
LOG_DIR=${LOG_DIR}
LOG_FILE=${LOG_FILE}" | tee -a "$LOG_FILE"

echo ""$RCLONE_BIN" mount \
  --read-only \
  --allow-non-empty \
  --allow-other \
  --buffer-size 1G \
  --max-read-ahead 14G \
  --acd-templink-threshold 0 \
  --checkers 16 \
  --quiet \
  --stats 0 \
  "${RCLONE_REMOTE_NAME}:${ENC_DIR_REMOTE}/" \
  "$ENC_DIR_LOCAL" | tee -a "$LOG_FILE"" | tee -a "$LOG_FILE"

"$RCLONE_BIN" mount \
  --read-only \
  --allow-non-empty \
  --allow-other \
  --buffer-size 1G \
  --max-read-ahead 14G \
  --acd-templink-threshold 0 \
  --checkers 16 \
  --quiet \
  --stats 0 \
  "${RCLONE_REMOTE_NAME}:${ENC_DIR_REMOTE}/" \
  "$ENC_DIR_LOCAL" | tee -a "$LOG_FILE" \
  ;
