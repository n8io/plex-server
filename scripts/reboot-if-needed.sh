#!/bin/bash
# Reboot when an update needs it, but only while nobody is streaming.
# A systemd timer runs this nightly; a busy night just waits for the next one.
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

LOG_FILE="${PLEX_CODE_DIR}/logs/updates.log"

if [ ! -f /var/run/reboot-required ]; then
  log_info "No reboot needed." "$LOG_FILE"
  exit 0
fi

# Livepatch covers most kernel fixes; a pending reboot then waits for a quiet night.
STREAMS="$("${PLEX_CODE_DIR}/scripts/plex-sessions.sh")"
if [ "${STREAMS:-0}" != "0" ]; then
  log_info "Reboot needed ($(tr '\n' ' ' < /var/run/reboot-required.pkgs 2>/dev/null)) but ${STREAMS} stream(s) active; trying tomorrow." "$LOG_FILE"
  exit 0
fi

log_info "Rebooting for: $(tr '\n' ' ' < /var/run/reboot-required.pkgs 2>/dev/null)" "$LOG_FILE"
systemctl reboot
