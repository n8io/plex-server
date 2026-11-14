#!/bin/bash
# Install the guarded nightly Plex "Empty Trash" job (see addons/plex-trash-clean/README.md).
# Idempotent: re-run after pulling to deploy script changes. Keeps /etc/plex-trash-clean.env.
set -e
DIR="$(dirname "$(realpath "$0")")/plex-trash-clean"
install -m 755 "$DIR/plex-trash-clean.sh" /usr/local/sbin/plex-trash-clean.sh
echo '45 4 * * * root /usr/local/sbin/plex-trash-clean.sh' > /etc/cron.d/plex-trash-clean
[ -e /etc/plex-trash-clean.env ] || { install -m 600 /dev/null /etc/plex-trash-clean.env; echo "Add PUSHBULLET_TOKEN=... to /etc/plex-trash-clean.env for alerts."; }
echo "Installed. Dry run: DRY_RUN=1 /usr/local/sbin/plex-trash-clean.sh && tail -n 5 /var/log/plex-trash-clean.log"
