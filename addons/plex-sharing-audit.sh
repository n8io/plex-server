#!/bin/bash
# Install the quarterly Plex account-sharing audit (see addons/plex-sharing-audit/README.md).
# Idempotent: re-run after pulling to deploy script changes. Keeps /etc/plex-sharing-audit.env.
set -e
DIR="$(dirname "$(realpath "$0")")/plex-sharing-audit"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-maxminddb >/dev/null
install -m 755 "$DIR/plex-sharing-audit.py" /usr/local/sbin/plex-sharing-audit.py
# 14:00 UTC (9 AM ET) on the 1st of Jan, Apr, Jul and Oct
echo '0 14 1 1,4,7,10 * root /usr/local/sbin/plex-sharing-audit.py >/dev/null 2>&1' > /etc/cron.d/plex-sharing-audit
[ -e /etc/plex-sharing-audit.env ] || { install -m 600 "$DIR/plex-sharing-audit.env.example" /etc/plex-sharing-audit.env; echo "Fill in /etc/plex-sharing-audit.env."; }
echo "Installed. Try it: /usr/local/sbin/plex-sharing-audit.py --no-email (or without the flag to email the report)"
