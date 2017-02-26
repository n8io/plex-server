#!/bin/bash
set -e

BASHRC="/root/.bashrc"
PLEX_CODE_DIR=$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
ENV_FILE="${PLEX_CODE_DIR}/.env"

PREV_REMOTE_DIR="${ENC_DIR_REMOTE:-/encrypted}"
PREV_MOUNT_DIR="${MOUNT_DIR:-/mnt/x}"
PREV_ENCFS_CREDS="${ENCFS_CREDS:-/.encfs}"
PREV_ENCFS6_CONFIG="${ENCFS6_CONFIG:-/encfs.xml}"
PREV_RCLONE_CONFIG="${RCLONE_CONFIG:-/root/.rclone.conf}"

prompt_for_creds() {
  MSG="  Enter your encryption password"

  if [ -f "$PREV_ENCFS_CREDS" ]; then
    MSG="${MSG} or hit enter to use existing [existing]"
  fi

  MSG="${MSG}: "
  echo -n "$MSG"
  read ENCFS_PWD

  MSG="  Paste in your encryption config"
  if [ -f "$PREV_ENCFS6_CONFIG" ]; then
    MSG="${MSG} or hit enter to use existing [existing]"
  fi

  MSG="${MSG}: "
  echo -n "$MSG"
  IFS= read -d '' -n 1 ENCFS_CONFIG_DATA
  while IFS= read -d '' -n 1 -t 1 c
  do
    ENCFS_CONFIG_DATA+=$c
  done

  ENCFS_CONFIG_DATA=$(echo -e "$ENCFS_CONFIG_DATA" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  if [ ! -z "$ENCFS_PWD" ]; then
    echo "$ENCFS_PWD" > "$PREV_ENCFS_CREDS"
  fi

  if [ ! -z "$ENCFS_CONFIG_DATA" ]; then
    echo "$ENCFS_CONFIG_DATA" > "$PREV_ENCFS6_CONFIG"
  fi

  return 0
}

prompt_for_settings() {
  echo -n "  Enter your Amazon Cloud Drive encrypted directory [${PREV_REMOTE_DIR}]: "
  read ENC_DIR_REMOTE
  echo -n "  Enter the path to where you want everything to be mounted [${PREV_MOUNT_DIR}]: "
  read MOUNT_DIR
  echo -n "  Enter the path to your ENCFS encryption password file [${PREV_ENCFS_CREDS}]: "
  read ENCFS_CREDS
  echo -n "  Enter the path to your ENCFS encryption config file [${PREV_ENCFS6_CONFIG}]: "
  read ENCFS6_CONFIG

  wipe_old # remove previous settings
  write_bashrc # write bashrc hooks
  write_env \
    "${ENC_DIR_REMOTE:-${PREV_REMOTE_DIR}}" \
    "${ENCFS_CREDS:-${PREV_ENCFS_CREDS}}" \
    "${ENCFS6_CONFIG:-${PREV_ENCFS6_CONFIG}}" \
    "${MOUNT_DIR:-${PREV_MOUNT_DIR}}" \
    ;

  return 0
}

prompt_for_rclone() {
  MSG="  Paste in your rclone config"
  if [ -f "$PREV_RCLONE_CONFIG" ]; then
    MSG="${MSG} or hit enter to use existing [existing]"
  fi

  MSG="${MSG}: "
  echo -n "$MSG"
  IFS= read -d '' -n 1 RCLONE_CONFIG_DATA
  while IFS= read -d '' -n 1 -t 1 c
  do
    RCLONE_CONFIG_DATA+=$c
  done

  RCLONE_CONFIG_DATA=$(echo -e "$RCLONE_CONFIG_DATA" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  if [ ! -z "$RCLONE_CONFIG_DATA" ]; then
    echo "$RCLONE_CONFIG_DATA" > "$PREV_RCLONE_CONFIG"
  fi

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

. "${PLEX_CODE_DIR}/.env"
. "${PLEX_CODE_DIR}/scripts/helper-functions.sh"
cd "$PLEX_CODE_DIR"

#plex-settings-end
EOT

echo "done."
}

write_env() {
echo -n "  Writing environment variables to ${ENV_FILE}..."
rm -rf "${ENV_FILE:?not set}"
cat <<EOT >> "$ENV_FILE"
export \\
  EDITOR="nano" \\
  ENC_DIR_REMOTE="${1:-/encrypted}" \\
  ENCFS_CREDS="${2:-/.encfs}" \\
  ENCFS6_CONFIG="${3:-/encfs.xml}" \\
  ENCFS_BIN="/usr/bin/encfs" \\
  ENCFS_CTL_BIN="/usr/bin/encfsctl" \\
  MOUNT_DIR="${4:-/mnt/x}" \\
  PLEX_CODE_DIR="$PLEX_CODE_DIR" \\
  RCLONE_BIN="/usr/sbin/rclone" \\
  ;

export \\
  ENC_DIR_LOCAL="\${MOUNT_DIR}/encrypted" \\
  DEC_DIR_LOCAL="\${MOUNT_DIR}/decrypted" \\
  ;
EOT

chmod a+x "$ENV_FILE"

echo "done."
}

misc() {
  mkdir -p "${PLEX_CODE_DIR}/logs"
  touch "${PLEX_CODE_DIR}/logs/rclone-mount.log"
  touch "${PLEX_CODE_DIR}/logs/mount-check.log"
}

echo "bashrc updating..."
prompt_for_settings # ask for settings
prompt_for_creds # ask for encryption info
prompt_for_rclone # ask for rclone info
misc # miscellaneous prep work
MSG="bashrc updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
