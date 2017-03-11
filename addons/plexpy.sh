#!/bin/bash
set -e

PLEXPY_INSTALL_DIR="/opt/plexpy"

plexpy_install() {
  if [ ! -d "$PLEXPY_INSTALL_DIR" ]; then
  	git clone https://github.com/JonnyWong16/plexpy.git "$PLEXPY_INSTALL_DIR"
  fi

  PLEXPY_SERVICE_DEF="/etc/systemd/system/plexpy.service"
  if [ ! -f "$PLEXPY_SERVICE_DEF" ]; then
    cat <<EOT >> "$PLEXPY_SERVICE_DEF"
[Unit]
Description=PlexPy - Stats for Plex Media Server usage

[Service]
ExecStart=/opt/plexpy/PlexPy.py --quiet --daemon --nolaunch --config /opt/plexpy/config.ini --datadir /opt/plexpy
GuessMainPID=no
Type=forking
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOT
fi
  systemctl enable plexpy
  service plexpy start
}

echo "Installing PlexPy..."
plexpy_install # plexpy
echo "done."

set +e
