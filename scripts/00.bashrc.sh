#!/bin/bash
set -e

BASHRC="/root/.bashrc"

wipe_old() {
  echo -n "  Removing previous plex settings from ${BASHRC}..."

  sed -i '/[#]plex[-]settings[-]start/,/[#]plex[-]settings[-]end/ d' "$BASHRC"

  echo "done."
}

write_new() {
echo -n "  Writing new plex settings to ${BASHRC}..."

cat <<EOT >> "$BASHRC"
#plex-settings-start

export \\
  ACD_MOUNT_DIR="/mnt/x" \\
  EDITOR="nano" \\
  ENC_DIR_REMOTE="/_/encrypted" \\
  ENCFS_CREDS="/.encfs" \\
  ENCFS6_CONFIG="/encfs.xml" \\
  ENCFS_BIN="/usr/bin/encfs" \\
  PLEX_CODE_DIR="/plex-server" \\
  RCLONE_BIN="/usr/sbin/rclone" \\
  ;

export \\
  ENC_DIR_LOCAL="$${ACD_MOUNT_DIR}/encrypted" \\
  DEC_DIR_LOCAL="$${ACD_MOUNT_DIR}/decrypted" \\
  ;

#plex-settings-end
EOT

echo "done."
}

echo "bashrc updating..."
wipe_old # remove previous settings
write_new # write new values
MSG="bashrc updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"
