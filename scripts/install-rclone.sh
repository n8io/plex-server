#!/bin/bash
# Install the latest stable rclone, checksum-verified against rclone's
# published sums. Prints the installed version. Used by setup/01 and the
# monthly rclone-update timer.
set -e

RCLONE_BIN="${RCLONE_BIN:-/usr/sbin/rclone}"
RCLONE_BASE="https://downloads.rclone.org"
RCLONE_VERSION="$(curl -fsSL "${RCLONE_BASE}/version.txt" | sed 's/^rclone //')"

if [ "${1:-}" = "--if-newer" ] && [ -x "$RCLONE_BIN" ] && "$RCLONE_BIN" version | head -n 1 | grep -qF "$RCLONE_VERSION"; then
  echo "rclone ${RCLONE_VERSION} already installed"
  exit 0
fi

RCLONE_ZIP="rclone-${RCLONE_VERSION}-linux-amd64.zip"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
cd "$TMP_DIR"
curl -fsSL -o "$RCLONE_ZIP" "${RCLONE_BASE}/${RCLONE_VERSION}/${RCLONE_ZIP}"
curl -fsSL -o SHA256SUMS "${RCLONE_BASE}/${RCLONE_VERSION}/SHA256SUMS"
if ! grep -q "^$(sha256sum "$RCLONE_ZIP" | cut -d' ' -f1)  ${RCLONE_ZIP}\$" SHA256SUMS; then
  echo "rclone ${RCLONE_VERSION}: checksum mismatch, not installed" >&2
  exit 1
fi
unzip -oq "$RCLONE_ZIP"
install -o root -g root -m 755 "rclone-${RCLONE_VERSION}-linux-amd64/rclone" "$RCLONE_BIN"
echo "rclone ${RCLONE_VERSION} installed"
