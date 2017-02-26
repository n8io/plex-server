#!/bin/bash
set -e

SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

write_job() {
  EXISTS=$(crontab -l | grep -q "${2}" && echo 1 || echo 0)

  if [ "$EXISTS" = "0" ]; then
    echo "Writing cron job for ${2}"
    (crontab -l 2>/dev/null; echo "${1} ${2}") | crontab -
  else
    echo "Cron job for ${2} already exists!"
  fi
}

echo "Cron jobs updating..."
write_job "* * * * *" "${PLEX_CODE_DIR}/scripts/mount-check.sh" # Check every minute that things are mounted
write_job "1 8 * * *" "${PLEX_CODE_DIR}/scripts/logs-cleanup.sh" # ~3:01am Eastern
write_job "2 9 * * *" "${PLEX_CODE_DIR}/scripts/cycle-mount.sh" # ~4:02am Eastern
MSG="Cron jobs updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
