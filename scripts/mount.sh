#!/bin/bash
# rclone mount, run in the foreground by systemd (rclone-media / rclone-photos).
#
#   mount.sh media    encrypted media at $ENC_DIR_LOCAL, with the local VFS cache
#   mount.sh photos   plain workout videos at $PHOTOS_DIR_LOCAL, no cache
#
# exec hands the process to systemd, so rclone's readiness signal (Type=notify)
# and restarts on failure work without screen or cron.
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

MOUNT_NAME="${1:-media}"

RCLONE_BIN="${RCLONE_BIN:-/usr/sbin/rclone}"
RCLONE_CONFIG="${RCLONE_CONFIG:-/root/.rclone.conf}"
RCLONE_REMOTE_NAME="${RCLONE_REMOTE_NAME:-$("$RCLONE_BIN" --config "$RCLONE_CONFIG" listremotes | head -n 1 | sed -e 's/\(:\)*$//g')}"
LOG_DIR="${LOG_DIR:-${PLEX_CODE_DIR}/logs}"
# Local disk cache for media read through the mount. Anything played once is
# served from here (LRU, capped by RCLONE_CACHE_MAX_SIZE) instead of the cloud.
# It is disposable: put it on unmirrored disk if you can (see README).
RCLONE_CACHE_DIR="${RCLONE_CACHE_DIR:-/home/rclone-cache}"
RCLONE_CACHE_MAX_SIZE="${RCLONE_CACHE_MAX_SIZE:-800G}"

case "$MOUNT_NAME" in
  media)
    REMOTE_DIR="${ENC_DIR_REMOTE:-/encrypted}"
    LOCAL_DIR="${ENC_DIR_LOCAL:-/mnt/x/encrypted}"
    mkdir -p "$RCLONE_CACHE_DIR"
    MODE_FLAGS=(
      --vfs-cache-mode full
      --cache-dir "$RCLONE_CACHE_DIR"
      --vfs-cache-max-size "$RCLONE_CACHE_MAX_SIZE"
      --vfs-cache-max-age 720h
      --vfs-read-ahead 512M
    )
    ;;
  photos)
    REMOTE_DIR="${PHOTOS_DIR_REMOTE:-/_/decrypted/workouts}"
    LOCAL_DIR="${PHOTOS_DIR_LOCAL:-/photos/Workouts}"
    MODE_FLAGS=(--vfs-cache-mode off)
    ;;
  *)
    echo "usage: mount.sh media|photos" >&2
    exit 2
    ;;
esac

mkdir -p "$LOCAL_DIR" "$LOG_DIR"

exec "$RCLONE_BIN" --config "$RCLONE_CONFIG" mount \
  --read-only \
  --allow-other \
  "${MODE_FLAGS[@]}" \
  --vfs-read-chunk-size 64M \
  --vfs-read-chunk-size-limit 2G \
  --buffer-size 32M \
  --dir-cache-time 9999h \
  --poll-interval 1m \
  --vfs-fast-fingerprint \
  --stats 0 \
  --log-level INFO \
  --log-file "${LOG_DIR}/rclone-${MOUNT_NAME}.log" \
  "${RCLONE_REMOTE_NAME}:${REMOTE_DIR}/" \
  "$LOCAL_DIR"
