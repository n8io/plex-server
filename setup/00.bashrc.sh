#!/bin/bash
set -e

BASHRC="/root/.bashrc"
CWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREV_REMOTE_DIR="${ENC_DIR_REMOTE:-/encrypted}"
PREV_LOCAL_DIR="${ENC_DIR_LOCAL:-/mnt/x}"
PREV_ENCFS_CREDS="${ENCFS_CREDS:-/.encfs}"
PREV_ENCFS6_CONFIG="${ENCFS6_CONFIG:-/encfs.xml}"

prompt_for_creds() {
  echo -n "  Enter your Amazon Cloud Drive encrypted directory [${PREV_REMOTE_DIR}]: "
  read ENC_DIR_REMOTE
  echo -n "  Enter the absolute path to where you want everything to be mounted [${PREV_LOCAL_DIR}]: "
  read ENC_DIR_LOCAL
  echo -n "  Enter the absolute path to your ENCFS encryption password file [${PREV_ENCFS_CREDS}]: "
  read ENCFS_CREDS
  echo -n "  Enter the absolute path to your ENCFS encryption config file [${PREV_ENCFS6_CONFIG}]: "
  read ENCFS6_CONFIG

  wipe_old # remove previous settings
  write_bashrc \ # write new values
    "${ENC_DIR_REMOTE:-${PREV_REMOTE_DIR}}" \
    "${ENC_DIR_LOCAL:-${PREV_LOCAL_DIR}}" \
    "${ENCFS_CREDS:-${PREV_ENCFS_CREDS}}" \
    "${ENCFS6_CONFIG:-${PREV_ENCFS6_CONFIG}}" \
    ;

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
  ACD_MOUNT_DIR="${2:-/encrypted}" \\
  EDITOR="nano" \\
  ENC_DIR_REMOTE="${1:-remote}" \\
  ENCFS_CREDS="${3:-/.encfs}" \\
  ENCFS6_CONFIG="${4:-/encfs.xml}" \\
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
