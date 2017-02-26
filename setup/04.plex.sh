#!/bin/bash
set -e

plex_install() {
  bash -c "$(wget -qO - https://raw.githubusercontent.com/mrworf/plexupdate/master/extras/installer.sh)" || true
}

update_sqlite() {
  echo -n "  Stopping Plex Media Server temporarily..."
  service plexmediaserver stop 2>/dev/null
  echo "done."

  echo -n "  Setting sqlite cache size..."
  sqlite3 -header -line \
    "/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db" \
    "PRAGMA default_cache_size = ${1:-1000000}" \
    ;
  echo "done."

  echo -n "  Starting Plex Media Server..."
  service plexmediaserver start
  echo "done."
}

echo "Plex Media Server installing..."
plex_install # plex
update_sqlite 1000000 # bump up sqlite cache size
MSG="Plex Media Server installed successfully."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
