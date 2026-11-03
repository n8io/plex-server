#!/bin/bash
# Nightly backup of everything needed to rebuild this box's Plex without
# rescanning: Plex's databases (consistent online copies), its Preferences
# (server identity), and the mount/app configs. Metadata (posters, ~20 GB) is
# left out: Plex re-downloads it.
#
# Keeps the last 3 here on mirrored disk; monitor/pull-backup.sh copies them
# off the box every night. Writes the time of the last good run for
# update-status.sh.
set -euo pipefail
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

PMS="${PLEX_APP_SUPPORT_DIR:-/var/lib/plexmediaserver/Library/Application Support}/Plex Media Server"
DB_DIR="${PMS}/Plug-in Support/Databases"
SQLITE="/usr/lib/plexmediaserver/Plex SQLite"
DEST="${PLEX_BACKUP_DIR:-/var/backups/plex}"
KEEP="${PLEX_BACKUP_KEEP:-3}"
LOG_FILE="${PLEX_CODE_DIR}/logs/backup.log"
STAMP="$(date -u +%Y%m%dT%H%MZ)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$DEST" "$WORK/db"
chmod 700 "$DEST"

# Online, consistent copies while Plex keeps running.
for db in com.plexapp.plugins.library.db com.plexapp.plugins.library.blobs.db; do
  [ -f "${DB_DIR}/${db}" ] || continue
  "$SQLITE" "${DB_DIR}/${db}" ".backup '${WORK}/db/${db}'"
  [ "$("$SQLITE" "${WORK}/db/${db}" 'PRAGMA quick_check;')" = "ok" ] || { log_error "backup: ${db} failed integrity check" "$LOG_FILE"; exit 1; }
done

OUT="${DEST}/plex-${STAMP}.tar.zst"
tar --zstd -cf "$OUT" \
  -C "$WORK" db \
  -C / \
  "${PMS#/}/Preferences.xml" \
  "${PLEX_CODE_DIR#/}/.env" \
  root/.rclone.conf \
  "${ENCFS6_CONFIG#/}" "${ENCFS_CREDS#/}" \
  $( [ -f /opt/plex-scan-ui/.env ] && echo opt/plex-scan-ui/.env ) \
  $( [ -f /opt/Tautulli/config.ini ] && echo opt/Tautulli/config.ini opt/Tautulli/tautulli.db ) \
  2>>"$LOG_FILE"
chmod 600 "$OUT"

ls -1t "$DEST"/plex-*.tar.zst | tail -n +$((KEEP + 1)) | xargs -r rm -f
date -u +%s > "${DEST}/last-success"
log_info "backup: $(basename "$OUT") $(du -h "$OUT" | cut -f1)" "$LOG_FILE"
