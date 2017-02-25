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
  echo -n "  Installing rclone..."
  cd / &&
  curl -O -s http://downloads.rclone.org/rclone-current-linux-amd64.zip >/dev/null &&
  unzip -oq rclone-current-linux-amd64.zip > /dev/null &&
  cd rclone-*-linux-amd64 &&
  cp rclone /usr/sbin/ &&
  chown root:root /usr/sbin/rclone &&
  chmod 755 /usr/sbin/rclone &&
  mkdir -p /usr/local/share/man/man1 &&
  cp rclone.1 /usr/local/share/man/man1/ &&
  mandb -q &&
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
