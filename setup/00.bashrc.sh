#!/bin/bash
set -e

BASHRC="/root/.bashrc"
CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

prompt_for_creds() {
  echo -n "  Enter your Amazon Cloud Drive encrypted directory [/encrypted]: "
  read ENC_DIR_REMOTE
  echo -n "  Enter the root path where you want everything to be mounted [/mnt/x]: "
  read ENC_DIR_LOCAL

  wipe_old # remove previous settings
  write_bashrc "${ENC_DIR_REMOTE:-/encrypted}" "${ENC_DIR_LOCAL:-/mnt/x}" # write new values

  return 0
}

wipe_old() {
  echo -n "  Removing previous plex settings from ${BASHRC}..."

  sed -i '/[#]plex[-]settings[-]start/,/[#]plex[-]settings[-]end/ d' "$BASHRC"

  echo "done."
}

write_bashrc() {
echo -n "  Writing new plex settings to ${BASHRC}..."

cat <<EOT >> "$BASHRC"
#plex-settings-start

export \\
  ACD_MOUNT_DIR="${2}" \\
  EDITOR="nano" \\
  ENC_DIR_REMOTE="${1}" \\
  ENCFS_CREDS="/.encfs" \\
  ENCFS6_CONFIG="/encfs.xml" \\
  ENCFS_BIN="/usr/bin/encfs" \\
  ENCFS_CTL_BIN="/usr/bin/encfsctl" \\
  PLEX_CODE_DIR="$CWD" \\
  RCLONE_BIN="/usr/sbin/rclone" \\
  ;

export \\
  ENC_DIR_LOCAL="\${ACD_MOUNT_DIR}/encrypted" \\
  DEC_DIR_LOCAL="\${ACD_MOUNT_DIR}/decrypted" \\
  ;

. "${CWD}/../scripts/helper-functions.sh"

cd "${CWD}/.."

#plex-settings-end
EOT

echo "done."
}

echo "bashrc updating..."
prompt_for_creds # ask for custom paths
MSG="bashrc updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"
