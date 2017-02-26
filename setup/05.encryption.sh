#!/bin/bash
set -e
. /root/.bashrc

unmount_encryption() {
  echo -n "  Unmounting encrypted dir..."
  fusermount -uz "$DEC_DIR_LOCAL" 2>/dev/null
  umount -l "$DEC_DIR_LOCAL" 2>/dev/null
  echo "done."
}

mount_encryption() {
  echo -n "  Mounting encrypted dir..."
  cat "$ENCFS_CREDS" | "$ENCFS_BIN" -S "$ENC_DIR_LOCAL" "$DEC_DIR_LOCAL" -- -o allow_other
  echo "done."
}

echo "Encryption mount updating..."
unmount_encryption # unmount encrypted dir
mount_encryption # mount encrypted dir
MSG="Encryption mount updated successfully."; \
echo -e "\e[32m${MSG}\e[0m"

set +e
