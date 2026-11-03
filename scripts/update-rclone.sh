#!/bin/bash
# Monthly: install a newer rclone if there is one, then restart the mounts
# onto it, but only while nobody is streaming. Until then the mounts keep
# running the old binary, which is harmless.
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

LOG_FILE="${PLEX_CODE_DIR}/logs/updates.log"

RESULT="$("${PLEX_CODE_DIR}/scripts/install-rclone.sh" --if-newer 2>&1)" || {
  log_error "rclone update failed: ${RESULT}" "$LOG_FILE"
  exit 1
}
log_info "$RESULT" "$LOG_FILE"

RUNNING="$(readlink -f "/proc/$(systemctl show -p MainPID --value rclone-media.service)/exe" 2>/dev/null)"
case "$RUNNING" in
  *"(deleted)"*) ;;   # the binary was replaced under the running mount
  *) exit 0 ;;
esac

# Wait up to 6 hours for a quiet moment.
for _ in $(seq 1 72); do
  if [ "$("${PLEX_CODE_DIR}/scripts/plex-sessions.sh")" = "0" ]; then
    log_info "Restarting mounts onto the new rclone." "$LOG_FILE"
    systemctl restart rclone-media.service rclone-photos.service
    exit 0
  fi
  sleep 300
done
log_info "Streams active for 6h; mounts stay on the old rclone until the next quiet restart." "$LOG_FILE"
