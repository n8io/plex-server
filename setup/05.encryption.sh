#!/bin/bash
set -e
. /root/.bashrc

unmount() {
  fusermount -uz "$1" 2>/dev/null || true
}

mount_encrypted() {
  echo -n "  Mounting encrypted dir..."
  "${PLEX_CODE_DIR}/scripts/mount.sh"
  sleep 3
  echo "done."
}

unmount_decrypted() {
  echo -n "  Unmounting decrypted dir..."
  unmount "$DEC_DIR_LOCAL"
  echo "done."
}

mount_decrypted() {
  echo -n "  Mounting decrypted dir..."
  cat "$ENCFS_CREDS" | "$ENCFS_BIN" -S -o allow_other "$ENC_DIR_LOCAL" "$DEC_DIR_LOCAL"
  echo "done."
}

echo "Encryption mount updating..."
mount_encrypted # mount the encrypted dir
unmount_decrypted # unmount encrypted dir
mount_decrypted # mount encrypted dir
MSG="Encryption mount updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
