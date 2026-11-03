#!/bin/bash
# Install Plex Scan UI (addons/plex-scan-ui) as a hardened systemd service on
# 127.0.0.1:8080. Reach it over Tailscale (setup/07.tailscale.sh).
#
# Needs /opt/plex-scan-ui/.env (root-only) with UI_USER, UI_PASS and either
# PLEX_TOKEN or PLEX_USERNAME + PLEX_PASSWORD. It's never committed.
set -e
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"

APP_DIR="/opt/plex-scan-ui"
APP_USER="plexscan"

if ! command -v node >/dev/null 2>&1; then
  echo -n "  Installing Node.js..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs >/dev/null
  echo "done."
fi

id "$APP_USER" >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER"

echo -n "  Copying app to ${APP_DIR}..."
mkdir -p "${APP_DIR}/public"
install -m 644 "${PLEX_CODE_DIR}/addons/plex-scan-ui/server.js" "${APP_DIR}/server.js"
install -m 644 "${PLEX_CODE_DIR}/addons/plex-scan-ui/public/index.html" "${APP_DIR}/public/index.html"
echo "done."

if [ ! -f "${APP_DIR}/.env" ]; then
  umask 077
  cat <<'EOT' > "${APP_DIR}/.env"
HOST=127.0.0.1
PORT=8080
PLEX_URL=http://127.0.0.1:32400
UI_USER=
UI_PASS=
PLEX_TOKEN=
EOT
  echo "  Created ${APP_DIR}/.env: fill in UI_USER, UI_PASS and PLEX_TOKEN, then: systemctl restart plex-scan-ui"
fi

install -m 644 "${PLEX_CODE_DIR}/systemd/plex-scan-ui.service" /etc/systemd/system/plex-scan-ui.service
systemctl daemon-reload
systemctl enable --now plex-scan-ui.service >/dev/null
echo -e "\e[32mPlex Scan UI installed.\e[0m"
