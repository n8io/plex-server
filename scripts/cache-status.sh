#!/bin/bash
# Show what the rclone VFS cache holds locally, in decrypted names.
#
#   cache-status.sh                 list every cached file: % downloaded, size, name
#   cache-status.sh <path>          one file or directory (relative to $DEC_DIR_LOCAL, or absolute)
#
# 100% = the whole file is on local disk and plays without touching the cloud.
# Anything < 100% is partially cached (rclone fetches 64M chunks on demand).
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

CACHE_DIR="${RCLONE_CACHE_DIR:-/home/rclone-cache}"
RCLONE_CONFIG="${RCLONE_CONFIG:-/root/.rclone.conf}"
RCLONE_REMOTE_NAME="${RCLONE_REMOTE_NAME:-$("$RCLONE_BIN" --config "$RCLONE_CONFIG" listremotes | head -n 1 | sed -e 's/:*$//')}"
VFS="${CACHE_DIR}/vfs/${RCLONE_REMOTE_NAME}${ENC_DIR_REMOTE}"
META="${CACHE_DIR}/vfsMeta/${RCLONE_REMOTE_NAME}${ENC_DIR_REMOTE}"
export ENCFS6_CONFIG
EXTPASS="cat ${ENCFS_CREDS}"

encode() { "$ENCFS_CTL_BIN" encode --extpass="$EXTPASS" "$ENC_DIR_LOCAL" "$1" 2>/dev/null; }
decode() { "$ENCFS_CTL_BIN" decode --extpass="$EXTPASS" "$ENC_DIR_LOCAL" "$1" 2>/dev/null; }

# $1 = encrypted path relative to the mount root
report() {
  local meta="${META}/$1"
  local name; name="$(decode "$1")"
  if [ ! -f "$meta" ]; then
    printf "%7s  %9s  %s\n" "-" "-" "$name"
    return
  fi
  python3 - "$meta" "$name" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
size = d.get("Size") or 0
have = sum(r["Size"] for r in d.get("Rs", []))
pct = (100.0 * have / size) if size else 0.0
print("%6.1f%%  %6.2f GB  %s" % (pct, size / 2.0**30, sys.argv[2]))
PY
}

list_under() { # $1 = encrypted dir relative to root ("" for everything)
  [ -d "${META}/$1" ] || return 0
  (cd "$META" && find "./$1" -type f | sed -e 's#^\./##') | while read -r f; do report "$f"; done | sort -k3
}

printf "%7s  %9s  %s\n" "cached" "size" "file"
if [ $# -eq 0 ]; then
  list_under ""
  echo
  du -sh "${CACHE_DIR}/vfs" 2>/dev/null | awk '{print "cache on disk: " $1}'
else
  p="${1#${DEC_DIR_LOCAL}/}"; p="${p%/}"
  enc="$(encode "$p")"
  if [ -d "${META}/${enc}" ]; then
    list_under "$enc"
  elif [ -f "${META}/${enc}" ]; then
    report "$enc"
  else
    echo "not cached: ${p}"
  fi
fi
