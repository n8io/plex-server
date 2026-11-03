#!/bin/bash
# Install Tautulli (stream history and stats for Plex) as a systemd service,
# reachable over the tailnet only: https://<node>.<tailnet>.ts.net:8443.
# After install, open it and connect it to Plex at 127.0.0.1:32400.
set -e

APP_DIR="/opt/Tautulli"
APP_USER="tautulli"
TAUTULLI_PORT="${TAUTULLI_PORT:-8181}"
TS_HTTPS_PORT="${TAUTULLI_TS_PORT:-8443}"

echo "Installing Tautulli..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git python3 python3-setuptools >/dev/null

id "$APP_USER" >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER"

if [ ! -d "${APP_DIR}/.git" ]; then
  git clone -q https://github.com/Tautulli/Tautulli.git "$APP_DIR"
fi
chown -R "${APP_USER}:${APP_USER}" "$APP_DIR"

cat <<EOT > /etc/systemd/system/tautulli.service
[Unit]
Description=Tautulli - stream history for Plex
After=network-online.target plexmediaserver.service

[Service]
ExecStart=/usr/bin/python3 ${APP_DIR}/Tautulli.py --config ${APP_DIR}/config.ini --datadir ${APP_DIR} --port ${TAUTULLI_PORT} --quiet --nolaunch
User=${APP_USER}
Group=${APP_USER}
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
ProtectSystem=full
ReadWritePaths=${APP_DIR}

[Install]
WantedBy=multi-user.target
EOT

systemctl daemon-reload
systemctl enable --now tautulli.service >/dev/null

# Tautulli updates itself in place (its own git pull); the firewall from
# setup/08.lockdown.sh keeps port ${TAUTULLI_PORT} off the internet.
if command -v tailscale >/dev/null 2>&1; then
  tailscale serve --bg --https="$TS_HTTPS_PORT" "http://127.0.0.1:${TAUTULLI_PORT}" >/dev/null
  echo "  Tailnet URL: https://$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))'):${TS_HTTPS_PORT}"
fi
echo -e "\e[32mTautulli installed.\e[0m"
