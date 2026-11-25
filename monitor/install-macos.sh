#!/bin/bash
# Install the off-box watchers as launchd jobs on a Mac:
#   io.n8.plex-watch    daily 10:05   updates, disks, backups, drift  (push only on problems)
#   io.n8.plex-uptime   every 5 min   media mounts + SSH, after 3 failures in a row (on change only)
#   io.n8.plex-backup   daily 04:30   pull the newest backup, keep 14
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$HOME/.config/plex-watch.env"
[ -f "$CONFIG" ] || { echo "Create $CONFIG first (PLEX_HOST, PLEX_SSH_KEY, PUSHBULLET_TOKEN), chmod 600." >&2; exit 1; }
chmod 600 "$CONFIG"
# shellcheck source=/dev/null
. "$CONFIG"

# The jobs need a key that works with nobody logged in (after a reboot the
# Keychain key isn't in ssh-agent and BatchMode can't unlock it).
KEY="${PLEX_SSH_KEY:-}"; KEY="${KEY/#\~/$HOME}"
if [ -z "$KEY" ]; then
  echo "Set PLEX_SSH_KEY=~/.ssh/plex_monitor in $CONFIG (see docs/monitor.md)." >&2; exit 1
fi
if [ ! -f "$KEY" ]; then
  ssh-keygen -q -t ed25519 -N '' -C "plex-monitor@$(hostname -s)" -f "$KEY"
  echo "New monitor key. Add this line to /root/.ssh/authorized_keys on the Plex server:"
  echo "  restrict $(cat "$KEY.pub")"
fi
ssh -o BatchMode=yes -o ConnectTimeout=15 -o IdentitiesOnly=yes -i "$KEY" "$PLEX_HOST" true \
  || echo "WARNING: $KEY can't log in to $PLEX_HOST yet; the jobs will alert until it can." >&2
rm -f "$HOME/.cache/plex-uptime.state"   # old single-file state (pre-2026-11-25)

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
