#!/bin/bash
# EncFS on top of the rclone mount, run in the foreground by systemd (encfs-media).
# Plex's libraries point at the decrypted side, $DEC_DIR_LOCAL.
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

mkdir -p "$DEC_DIR_LOCAL"

# ENCFS6_CONFIG (exported by .env) tells encfs where its config lives; the
# password comes from the creds file on stdin (-S).
exec "${ENCFS_BIN:-/usr/bin/encfs}" -f -S -o allow_other \
  "$ENC_DIR_LOCAL" "$DEC_DIR_LOCAL" < "$ENCFS_CREDS"
