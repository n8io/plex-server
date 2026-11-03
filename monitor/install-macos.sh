#!/bin/bash
# Install plex-watch.sh as a daily launchd job (10:05 local) on a Mac.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="io.n8.plex-watch"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
CONFIG="$HOME/.config/plex-watch.env"

[ -f "$CONFIG" ] || { echo "Create $CONFIG first (PLEX_HOST, SLACK_WEBHOOK_URL), chmod 600." >&2; exit 1; }
chmod 600 "$CONFIG"

cat <<EOT > "$PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>${DIR}/plex-watch.sh</string></array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>10</integer><key>Minute</key><integer>5</integer></dict>
  <key>StandardErrorPath</key><string>${HOME}/Library/Logs/plex-watch.log</string>
  <key>StandardOutPath</key><string>${HOME}/Library/Logs/plex-watch.log</string>
</dict>
</plist>
EOT
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed ${LABEL}; runs daily at 10:05."
