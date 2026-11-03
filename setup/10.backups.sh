#!/bin/bash
# Nightly Plex backup (scripts/backup-plex.sh) and the tools update-status.sh
# uses for disk health. The off-box copy is monitor/pull-backup.sh.
set -e
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"

echo "Backups updating..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq smartmontools zstd >/dev/null
for u in plex-backup.service plex-backup.timer; do
  sed -e "s|@PLEX_CODE_DIR@|${PLEX_CODE_DIR}|g" "${PLEX_CODE_DIR}/systemd/${u}" > "/etc/systemd/system/${u}"
done
systemctl daemon-reload
systemctl enable --now plex-backup.timer >/dev/null
systemctl list-timers --no-pager plex-backup.timer | head -2
echo -e "\e[32mBackups set up successfully.\e[0m"
