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

plex_custom_scanner_install() {
  echo -n "  Installing additional media scanners..."
  TMP_DIR="/temp/empa"; \
  PLEX_PLUGINS_DIR="${PLEX_PLUGINS_DIR:-/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Plug-ins}"; \
  wget -q -P "${TMP_DIR}/" "https://bitbucket.org/mjarends/extendedpersonalmedia-agent.bundle/get/master.zip" && \
  unzip -qq -o "${TMP_DIR}/master.zip" -d "$TMP_DIR" && \
  mv ${TMP_DIR}/mjarends-extendedpersonalmedia-agent.bundle-* "${TMP_DIR}/ExtendedPersonalMedia-Agent.bundle" && \
  mv "${TMP_DIR}/ExtendedPersonalMedia-Agent.bundle" "${PLEX_PLUGINS_DIR}/ExtendedPersonalMedia-Agent.bundle" && \
  chown -R plex:plex "$PLEX_PLUGINS_DIR/ExtendedPersonalMedia-Agent.bundle" && \
  service plexmediaserver restart && \
  rm -rf "${TMP_DIR:-?}" \
  ;
  echo "done."
}

echo "Plex Media Server installing..."
plex_install # plex
plex_custom_scanner_install # add custom scanner for those libraries that dont have typical metadata
update_sqlite 1000000 # bump up sqlite cache size
MSG="Plex Media Server installed successfully."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
