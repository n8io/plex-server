#!/bin/bash
set -e

PARENT_DIR="$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"

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
write_job "0 8 * * *" "${PARENT_DIR}/scripts/cycle-mount.sh" # ~4am Eastern
MSG="Cron jobs updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
