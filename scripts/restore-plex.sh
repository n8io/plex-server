#!/bin/bash
# Restore a backup made by backup-plex.sh onto this box.
#
#   restore-plex.sh /var/backups/plex/plex-<stamp>.tar.zst      from a file
#   restore-plex.sh - < backup.tar.zst                           from stdin
#
# Stops Plex, keeps the current databases and Preferences aside in
# <Databases>/pre-restore-<time>/, puts the backup's in place, restores the
# configs that are missing, and starts Plex again. Metadata is not in the
# backup; Plex refreshes posters on its own.
set -euo pipefail
SRC="${1:?usage: restore-plex.sh <backup.tar.zst|->}"
PMS="${PLEX_APP_SUPPORT_DIR:-/var/lib/plexmediaserver/Library/Application Support}/Plex Media Server"
DB_DIR="${PMS}/Plug-in Support/Databases"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$SRC" = "-" ]; then tar --zstd -xf - -C "$WORK"; else tar --zstd -xf "$SRC" -C "$WORK"; fi
[ -f "${WORK}/db/com.plexapp.plugins.library.db" ] || { echo "No Plex database in the backup." >&2; exit 1; }

echo "Stopping Plex..."
systemctl stop plexmediaserver

KEEP="${DB_DIR}/pre-restore-$(date -u +%Y%m%dT%H%MZ)"
mkdir -p "$KEEP"
mv "${DB_DIR}"/com.plexapp.plugins.library*.db* "$KEEP"/ 2>/dev/null || true
cp -a "${PMS}/Preferences.xml" "$KEEP"/ 2>/dev/null || true

install -o plex -g plex -m 644 "${WORK}"/db/*.db "$DB_DIR"/
install -o plex -g plex -m 600 "${WORK}/${PMS#/}/Preferences.xml" "${PMS}/Preferences.xml"

# Configs: only fill in what's missing, never overwrite this box's own.
( cd "$WORK" && find . -type f ! -path './db/*' ! -path "./${PMS#/}/*" -printf '%P\n' ) |
while read -r f; do
  [ -e "/$f" ] || { mkdir -p "$(dirname "/$f")"; cp -a "$WORK/$f" "/$f"; echo "  restored /$f"; }
done

echo "Starting Plex... (previous files kept in ${KEEP})"
systemctl start plexmediaserver
sleep 10
curl -fsS --max-time 10 http://127.0.0.1:32400/identity >/dev/null && echo "Plex is up." || echo "Plex didn't answer yet; check: systemctl status plexmediaserver"
