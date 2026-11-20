#!/bin/bash
# Install the quarterly Plex account-sharing audit REMINDER (see addons/plex-sharing-audit/README.md).
# The box only sends a Pushbullet reminder; Nate then asks Claude to run the audit.
# Idempotent: re-run after pulling. Keeps /etc/plex-sharing-audit.env.
set -e
DIR="$(dirname "$(realpath "$0")")/plex-sharing-audit"
install -m 755 "$DIR/plex-sharing-audit.py" /usr/local/sbin/plex-sharing-audit.py
# 14:00 UTC (9 AM ET) on the 1st of Jan, Apr, Jul and Oct
echo '0 14 1 1,4,7,10 * root /usr/local/sbin/plex-sharing-audit.py --remind >/dev/null 2>&1' > /etc/cron.d/plex-sharing-audit
if [ ! -e /etc/plex-sharing-audit.env ]; then
  install -m 600 "$DIR/plex-sharing-audit.env.example" /etc/plex-sharing-audit.env
  # reuse the box's Pushbullet token (same one plex-trash-clean alerts with)
  tok=$(grep -m1 '^PUSHBULLET_TOKEN=' /etc/plex-trash-clean.env 2>/dev/null | cut -d= -f2-)
  [ -n "$tok" ] && sed -i "s|^PUSHBULLET_TOKEN=.*|PUSHBULLET_TOKEN=$tok|" /etc/plex-sharing-audit.env
fi
echo "Installed. Test the reminder: /usr/local/sbin/plex-sharing-audit.py --remind"
