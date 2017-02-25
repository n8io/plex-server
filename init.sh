#!/bin/bash
set -e

"./setup/00.bashrc.sh"
. /root/.bashrc
"./setup/01.dependencies.sh"
"./setup/02.os-settings.sh"
"./setup/03.cron-jobs.sh"
"./setup/04.plex.sh"
