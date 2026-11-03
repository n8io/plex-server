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
    curl \
    fuse3 \
    glances \
    gpg \
    python3 \
    sqlite3 \
    unzip \
    >/dev/null \
    ;
  apt install -y encfs
  echo "done."
}

rclone_install() {
  echo -n "  Installing rclone..."
  RCLONE_BIN=/usr/sbin/rclone "$(dirname "$(realpath "$0")")/../scripts/install-rclone.sh" ||
  { echo "failed (download or checksum mismatch)"; exit 1; }
  # rclone >= 1.60 execs `fusermount3` via PATH; hosts with only FUSE 2 need a
  # shim. Put it in /usr/bin so cron's minimal PATH (/usr/bin:/bin) finds it too.
  if ! command -v fusermount3 >/dev/null 2>&1 && command -v fusermount >/dev/null 2>&1; then
    ln -sf "$(command -v fusermount)" /usr/bin/fusermount3
  fi
}

echo "Updating dependencies..."
apt_update # update the server in general
apt_install # install all the things!
rclone_install # rclone
MSG="Dependencies updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
