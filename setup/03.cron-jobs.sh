#!/bin/bash
set -e

SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

# Edit a copy of the crontab and install it once at the end; piping
# `crontab -l` into `crontab -` per job dropped entries on a fresh box.
CRON_FILE="$(mktemp)"
trap 'rm -f "$CRON_FILE"' EXIT
crontab -l 2>/dev/null > "$CRON_FILE" || true

write_job() {
  if grep -qF "${2}" "$CRON_FILE"; then
    echo "Cron job for ${2} already exists!"
  else
    echo "Writing cron job for ${2}"
    echo "${1} ${2}" >> "$CRON_FILE"
  fi
}

remove_job() {
  if grep -qF "${1}" "$CRON_FILE"; then
    echo "Removing cron job for ${1}"
    grep -vF "${1}" "$CRON_FILE" > "${CRON_FILE}.new" || true
    mv "${CRON_FILE}.new" "$CRON_FILE"
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
crontab "$CRON_FILE"
MSG="Cron jobs updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
