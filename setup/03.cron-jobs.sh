#!/bin/bash
set -e

SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

write_job() {
  EXISTS=$(crontab -l 2>/dev/null | grep -qF "${2}" && echo 1 || echo 0)

  if [ "$EXISTS" = "0" ]; then
    echo "Writing cron job for ${2}"
    (crontab -l 2>/dev/null; echo "${1} ${2}") | crontab -
  else
    echo "Cron job for ${2} already exists!"
  fi
}

remove_job() {
  if crontab -l 2>/dev/null | grep -qF "${1}"; then
    echo "Removing cron job for ${1}"
    crontab -l 2>/dev/null | grep -vF "${1}" | crontab -
  fi
}

echo "Cron jobs updating..."
# systemd now brings the mounts up at boot and restarts them if they die, so
# the @reboot remount and the nightly mount restart are gone. The nightly
# restart cut live streams and caused cache read errors right after it.
remove_job "${PLEX_CODE_DIR}/setup/05.encryption.sh"
remove_job "${PLEX_CODE_DIR}/scripts/cycle-mount.sh"
remove_job "${PLEX_CODE_DIR}/.temp/"
write_job "*/5 * * * *" "${PLEX_CODE_DIR}/scripts/mount-check.sh" # catch a mount that hangs without dying
write_job "1 8 * * *" "${PLEX_CODE_DIR}/scripts/logs-cleanup.sh" # ~3:01am Eastern
MSG="Cron jobs updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
