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
    screen \
    unzip \
    glances \
    screen \
    sqlite \
    >/dev/null \
    ;
  apt install -y encfs
  echo "done."
}

rclone_install() {
  # Latest stable release, checksum-verified against rclone's published sums.
  RCLONE_BASE="https://downloads.rclone.org"
  RCLONE_VERSION="$(curl -fsSL "${RCLONE_BASE}/version.txt" | sed 's/^rclone //')"
  RCLONE_ZIP="rclone-${RCLONE_VERSION}-linux-amd64.zip"
  TMP_DIR="$(mktemp -d)"
  echo -n "  Installing rclone ${RCLONE_VERSION}..."
  cd "$TMP_DIR" &&
  curl -fsSL -o "$RCLONE_ZIP" "${RCLONE_BASE}/${RCLONE_VERSION}/${RCLONE_ZIP}" &&
  curl -fsSL -o SHA256SUMS "${RCLONE_BASE}/${RCLONE_VERSION}/SHA256SUMS" &&
  grep -q "^$(sha256sum "$RCLONE_ZIP" | cut -d' ' -f1)  ${RCLONE_ZIP}\$" SHA256SUMS &&
  unzip -oq "$RCLONE_ZIP" &&
  install -o root -g root -m 755 "rclone-${RCLONE_VERSION}-linux-amd64/rclone" /usr/sbin/rclone ||
  { echo "failed (download or checksum mismatch)"; rm -rf "$TMP_DIR"; exit 1; }
  cd / && rm -rf "$TMP_DIR"
  # rclone >= 1.60 execs `fusermount3` via PATH; hosts with only FUSE 2 need a
  # shim. Put it in /usr/bin so cron's minimal PATH (/usr/bin:/bin) finds it too.
  if ! command -v fusermount3 >/dev/null 2>&1 && command -v fusermount >/dev/null 2>&1; then
    ln -sf "$(command -v fusermount)" /usr/bin/fusermount3
  fi
  echo "done."
}

echo "Updating dependencies..."
apt_update # update the server in general
apt_install # install all the things!
rclone_install # rclone
MSG="Dependencies updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
