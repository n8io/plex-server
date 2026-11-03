#!/bin/bash
# Install the off-box watchers as launchd jobs on a Mac:
#   io.n8.plex-watch    daily 10:05   updates, disks, backups, drift  (DM only on problems)
#   io.n8.plex-uptime   every 5 min   Plex reachable + mounts          (DM on change only)
#   io.n8.plex-backup   daily 04:30   pull the newest backup, keep 14
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$HOME/.config/plex-watch.env"
[ -f "$CONFIG" ] || { echo "Create $CONFIG first (PLEX_HOST, SLACK_WEBHOOK_URL), chmod 600." >&2; exit 1; }
chmod 600 "$CONFIG"

install_job() {  # label script schedule-xml
  local LABEL="$1" SCRIPT="$2" SCHEDULE="$3"
  local PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
  cat <<EOT > "$PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>${DIR}/${SCRIPT}</string></array>
  ${SCHEDULE}
  <key>StandardErrorPath</key><string>${HOME}/Library/Logs/${LABEL}.log</string>
  <key>StandardOutPath</key><string>${HOME}/Library/Logs/${LABEL}.log</string>
</dict>
</plist>
EOT
  launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "Installed ${LABEL}"
}

install_job io.n8.plex-watch plex-watch.sh \
  '<key>StartCalendarInterval</key><dict><key>Hour</key><integer>10</integer><key>Minute</key><integer>5</integer></dict>'
install_job io.n8.plex-uptime plex-uptime.sh '<key>StartInterval</key><integer>300</integer>'
install_job io.n8.plex-backup pull-backup.sh \
  '<key>StartCalendarInterval</key><dict><key>Hour</key><integer>4</integer><key>Minute</key><integer>30</integer></dict>'
