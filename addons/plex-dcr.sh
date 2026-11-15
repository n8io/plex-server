#!/bin/bash
# Install the weekly Plex DCR job (see addons/plex-dcr/README.md).
# Idempotent: re-run after pulling to deploy script changes. Keeps /etc/plex-dcr.env.
set -e
DIR="$(dirname "$(realpath "$0")")/plex-dcr"
install -m 755 "$DIR/plex-dcr.py" /usr/local/sbin/plex-dcr.py
echo '0 14 * * 1 root /usr/local/sbin/plex-dcr.py >/dev/null 2>&1' > /etc/cron.d/plex-dcr
[ -e /etc/plex-dcr.env ] || { install -m 600 "$DIR/plex-dcr.env.example" /etc/plex-dcr.env; echo "Fill in /etc/plex-dcr.env (starts with DRY_RUN=1)."; }
echo "Installed. Try it: /usr/local/sbin/plex-dcr.py; tail -n 5 /var/log/plex-dcr.log"
