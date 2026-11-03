#!/bin/bash
set -e

"./setup/00.bashrc.sh"
. ./.env
"./setup/01.dependencies.sh"
"./setup/02.os-settings.sh"
"./setup/03.cron-jobs.sh"
"./setup/04.plex.sh"
"./setup/05.encryption.sh"
"./setup/07.tailscale.sh"

echo
echo "Next: sign in to Plex at http://localhost:32400/web (SSH tunnel, see README),"
echo "then run ./setup/06.plex-settings.sh and ./addons/plex-scan-ui.sh."
