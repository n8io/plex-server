#!/bin/bash
# Restart the media mounts. EncFS restarts with rclone (PartOf=rclone-media).
#
#   cycle-mount.sh          media (rclone + EncFS)
#   cycle-mount.sh photos   the workout videos mount
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

LOG_FILE="${PLEX_CODE_DIR}/logs/mount-check.log"

case "${1:-media}" in
  media)  UNIT="rclone-media.service" ;;
  photos) UNIT="rclone-photos.service" ;;
  *) echo "usage: cycle-mount.sh [media|photos]" >&2; exit 2 ;;
esac

log_info "Restarting ${UNIT}..." "$LOG_FILE"
systemctl restart "$UNIT"
