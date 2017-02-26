#!/bin/bash
set -e

apt_update() {
  echo -n "  Updating apt..."
  apt-get -qq update >/dev/null
  echo -n "done."
}

apt_install() {
  echo -n "  Installing dependencies..."
  apt-get install -y \
    glances \
    screen \
    sqlite \
    >/dev/null \
    ;
  apt install -y encfs
  echo "done."
}

rclone_install() {
  # RCLONE_VERSION_BASE="http://downloads.rclone.org"
  RCLONE_VERSION_BASE="http://beta.rclone.org/"
  # RCLONE_VERSION="rclone-current-linux-amd64"
  RCLONE_VERSION="rclone-beta-latest-linux-amd64"
  echo -n "  Installing rclone..."
  cd / &&
  curl -O -s "${RCLONE_VERSION_BASE}/${RCLONE_VERSION}.zip" >/dev/null &&
  unzip -oq "${RCLONE_VERSION}.zip" > /dev/null &&
  cd rclone-*-linux-amd64 &&
  cp rclone /usr/bin/ &&
  chown root:root /usr/bin/rclone &&
  chmod 755 /usr/bin/rclone &&
  rm -rf /rclone-*
  echo "done."
}


echo "Updating dependencies..."
apt_update # update the server in general
apt_install # install all the things!
rclone_install # rclone
MSG="Dependencies updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
