#!/bin/bash
set -e

PLEX_KEYRING="/etc/apt/keyrings/plexmediaserver.v2.gpg"
PLEX_SOURCES="/etc/apt/sources.list.d/plexmediaserver.list"

# Plex's own apt repo (moved to repo.plex.tv with a v2 key as of PMS 1.43.0),
# so Plex updates arrive with normal OS updates (below) instead of a separate
# plexupdate cron.
plex_install() {
  echo -n "  Adding Plex's apt repo..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://downloads.plex.tv/plex-keys/PlexSign.v2.key | gpg --dearmor --yes -o "$PLEX_KEYRING"
  echo "deb [signed-by=${PLEX_KEYRING}] https://repo.plex.tv/deb/ public main" > "$PLEX_SOURCES"
  apt-get -qq update >/dev/null
  echo "done."

  echo -n "  Installing Plex Media Server..."
  # confold keeps our sources file if the package offers to replace it.
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::=--force-confold plexmediaserver >/dev/null
  echo "done."
}

# Security updates for the OS, plus Plex from its repo, install unattended.
auto_updates() {
  echo -n "  Turning on automatic updates..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades >/dev/null
  cat <<'EOT' > /etc/apt/apt.conf.d/51plex-unattended
Unattended-Upgrade::Origins-Pattern {
  "origin=Ubuntu,archive=${distro_codename}-security";
  "site=repo.plex.tv";
};
// Reboots are manual: a reboot drops every stream.
Unattended-Upgrade::Automatic-Reboot "false";
EOT
  cat <<'EOT' > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOT
  echo "done."
}

# Legacy agent for libraries without standard metadata. Only needed if a
# library still uses it.
plex_custom_scanner_install() {
  echo -n "  Installing additional media scanners..."
  TMP_DIR="/temp/empa"; \
  PLEX_PLUGINS_DIR="${PLEX_PLUGINS_DIR:-/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Plug-ins}"; \
  wget -q -P "${TMP_DIR}/" "https://bitbucket.org/mjarends/extendedpersonalmedia-agent.bundle/get/master.zip" && \
  unzip -qq -o "${TMP_DIR}/master.zip" -d "$TMP_DIR" && \
  mv ${TMP_DIR}/mjarends-extendedpersonalmedia-agent.bundle-* "${TMP_DIR}/ExtendedPersonalMedia-Agent.bundle" && \
  mv "${TMP_DIR}/ExtendedPersonalMedia-Agent.bundle" "${PLEX_PLUGINS_DIR}/ExtendedPersonalMedia-Agent.bundle" && \
  chown -R plex:plex "$PLEX_PLUGINS_DIR/ExtendedPersonalMedia-Agent.bundle" && \
  systemctl restart plexmediaserver && \
  rm -rf "${TMP_DIR:-?}" \
  ;
  echo "done."
}

echo "Plex Media Server installing..."
plex_install # plex
auto_updates # OS security + Plex updates
[ "${INSTALL_EXTENDED_AGENT:-0}" = "1" ] && plex_custom_scanner_install
MSG="Plex Media Server installed successfully. Sign in at http://localhost:32400/web, then run setup/06.plex-settings.sh."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
