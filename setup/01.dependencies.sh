#!/bin/bash
set -e

apt_update() {
  echo -n "  Updating apt..."
  apt -qq update >/dev/null
  echo -n "done."
}

apt_install() {
  echo -n "  Installing dependencies..."
  apt install -y \
    glances \
    git \
    sqlite \
    >/dev/null \
    ;
  apt install -y encfs
  echo "done."
}

rclone_install() {
  # RCLONE_VERSION_BASE="http://downloads.rclone.org"
  RCLONE_VERSION_BASE="http://beta.rclone.org/v1.35-129-g980cd5b"
  # RCLONE_VERSION="rclone-current-linux-amd64"
  RCLONE_VERSION="rclone-v1.35-129-g980cd5bβ-linux-amd64"
  echo -n "  Installing rclone..."
  cd / &&
  curl -O -s "${RCLONE_VERSION_BASE}/${RCLONE_VERSION}.zip" >/dev/null &&
  unzip -oq "${RCLONE_VERSION}.zip" > /dev/null &&
  cd rclone-*-linux-amd64 &&
  cp rclone /usr/sbin/ &&
  chown root:root /usr/sbin/rclone &&
  chmod 755 /usr/sbin/rclone &&
  mkdir -p /usr/local/share/man/man1 &&
  rm /rclone-current*
  echo "done."
}


echo "Updating dependencies..."
apt_update # update the server in general
apt_install # install all the things!
rclone_install # rclone
MSG="Dependencies updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
