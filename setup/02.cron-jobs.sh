#!/bin/bash
set -e

CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

write_job() {
  EXISTS=$(crontab -l | grep -q "${2}" && echo 1 || echo 0)

  if [ "$EXISTS" = "0" ]; then
    echo "Writing cron job for ${2}"
    (crontab -l 2>/dev/null; echo "${1} . $HOME/.bashrc; ${2}") | crontab -
  else
    echo "Cron job for ${2} already exists!"
  fi
}

write_job "*/15 * * * *" "${CWD}/../scripts/cycle-mount.sh"

set +e
