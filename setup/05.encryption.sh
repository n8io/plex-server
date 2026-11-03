#!/bin/bash
set -e
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

UNIT_DIR="/etc/systemd/system"
PHOTOS_DIR_LOCAL="${PHOTOS_DIR_LOCAL:-/photos/Workouts}"

# Copy a unit from systemd/, filling in this box's paths.
install_unit() {
  sed \
    -e "s|@PLEX_CODE_DIR@|${PLEX_CODE_DIR}|g" \
    -e "s|@ENC_DIR_LOCAL@|${ENC_DIR_LOCAL}|g" \
    -e "s|@DEC_DIR_LOCAL@|${DEC_DIR_LOCAL}|g" \
    -e "s|@PHOTOS_DIR_LOCAL@|${PHOTOS_DIR_LOCAL}|g" \
    "${PLEX_CODE_DIR}/systemd/${1}" > "${UNIT_DIR}/${2:-$1}"
}

retire_screen_mounts() {
  echo -n "  Stopping old screen-based mounts..."
  screen -ls 2>/dev/null | grep -E "\.(rclone-mount|photo-rclone-mount)" | cut -d. -f1 | awk '{print $1}' | xargs -r kill 2>/dev/null || true
  fusermount3 -uz "$DEC_DIR_LOCAL" 2>/dev/null || true
  fusermount3 -uz "$ENC_DIR_LOCAL" 2>/dev/null || true
  fusermount3 -uz "$PHOTOS_DIR_LOCAL" 2>/dev/null || true
  echo "done."
}

install_units() {
  echo -n "  Installing systemd units..."
  install_unit rclone-media.service
  install_unit rclone-photos.service
  install_unit encfs-media.service
  mkdir -p "${UNIT_DIR}/plexmediaserver.service.d"
  install_unit plexmediaserver-override.conf plexmediaserver.service.d/override.conf
  systemctl daemon-reload
  echo "done."
}

start_mounts() {
  echo -n "  Starting mounts..."
  systemctl enable --now rclone-media.service rclone-photos.service encfs-media.service >/dev/null
  echo "done."
}

echo "Encryption mounts updating..."
retire_screen_mounts
install_units
start_mounts
systemctl --no-pager --lines=0 status rclone-media.service encfs-media.service rclone-photos.service || true
MSG="Encryption mounts updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
