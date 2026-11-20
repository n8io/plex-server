#!/bin/bash
# Install the newest Plex Media Server for our channel, but only while nobody
# is streaming. Plex's apt repo only carries public releases, so this pulls
# from plex.tv's downloads API instead (which also knows Plex Pass betas).
# Run hourly by plex-update.timer; a busy hour just waits for the next one.
#
# Config (from .env, /etc/plex-update.env or the environment):
#   PLEX_UPDATE_CHANNEL=beta|public   (default beta = Plex Pass releases)
#   PUSHBULLET_TOKEN=...              (alerts; falls back to /etc/plex-trash-clean.env)
#   DRY_RUN=1                         (say what would happen, change nothing)
#
# Safety: checksum-verified download, 0 streams required, health check after
# install, automatic reinstall of the previous build if Plex doesn't come back.
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env" >/dev/null 2>&1
[ -r /etc/plex-update.env ] && . /etc/plex-update.env
[ -z "${PUSHBULLET_TOKEN:-}" ] && [ -r /etc/plex-trash-clean.env ] && . /etc/plex-trash-clean.env

CHANNEL="${PLEX_UPDATE_CHANNEL:-beta}"
LOG_FILE="${PLEX_CODE_DIR}/logs/updates.log"
CACHE_DIR=/var/cache/plex-update
PLEX_PREFS="${PLEX_APP_SUPPORT_DIR:-/var/lib/plexmediaserver/Library/Application Support}/Plex Media Server/Preferences.xml"
PLEX_TOKEN="${PLEX_TOKEN:-$(grep -oE 'PlexOnlineToken="[^"]+"' "$PLEX_PREFS" 2>/dev/null | cut -d'"' -f2)}"
HOST="$(hostname)"

log() {
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') [plex-update] $*" | tee -a "$LOG_FILE"
}

push() { # title, body
  [ -n "${PUSHBULLET_TOKEN:-}" ] || return 0
  python3 -c 'import json,sys; print(json.dumps({"type":"link","title":sys.argv[1],"body":sys.argv[2],"url":"https://app.plex.tv/desktop/#!/settings/server/"}))' "$1" "$2" \
    | curl -sS -m 15 -H "Access-Token: $PUSHBULLET_TOKEN" -H 'Content-Type: application/json' \
        --data-binary @- https://api.pushbullet.com/v2/pushes >/dev/null \
    || log "pushbullet send failed"
}

plex_healthy() { # wait up to 3 min for Plex to answer
  for _ in $(seq 1 36); do
    curl -fsS --max-time 5 http://127.0.0.1:32400/identity >/dev/null 2>&1 && return 0
    sleep 5
  done
  return 1
}

fetch_deb() { # url, sha1, dest
  curl -fsSL --max-time 600 -o "$3.part" "$1" || return 1
  echo "$2  $3.part" | sha1sum -c --quiet - >/dev/null 2>&1 || { rm -f "$3.part"; return 1; }
  mv "$3.part" "$3"
}

install_deb() {
  DEBIAN_FRONTEND=noninteractive dpkg -i --force-confold "$1" >>"$LOG_FILE" 2>&1
}

case "$CHANNEL" in
  beta) API_CHANNEL=plexpass ;;
  public) API_CHANNEL=public ;;
  *) log "unknown PLEX_UPDATE_CHANNEL=$CHANNEL"; exit 1 ;;
esac

CURRENT="$(dpkg-query -W -f='${Version}' plexmediaserver 2>/dev/null)"
[ -n "$CURRENT" ] || { log "plexmediaserver isn't installed; nothing to update."; exit 0; }

# Newest 64-bit Debian build for our channel. The Plex Pass channel needs the
# server's token; without one plex.tv quietly answers with the public build.
LATEST_JSON="$(curl -fsS --max-time 30 -H "X-Plex-Token: ${PLEX_TOKEN}" \
  "https://plex.tv/api/downloads/5.json?channel=${API_CHANNEL}")" || { log "couldn't reach plex.tv downloads API"; exit 1; }
read -r LATEST URL SHA1 < <(echo "$LATEST_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)["computer"]["Linux"]
for r in d["releases"]:
    if r["build"] == "linux-x86_64" and r["distro"] == "debian":
        print(d["version"], r["url"], r["checksum"]); break
')
[ -n "$LATEST" ] && [ -n "$URL" ] || { log "no linux-x86_64 debian build in plex.tv answer"; exit 1; }

if dpkg --compare-versions "$LATEST" le "$CURRENT"; then
  log "Plex $CURRENT is current for the $CHANNEL channel."
  exit 0
fi

# A build that already failed and was rolled back isn't retried; the next
# release is. Delete this file to force a retry.
BAD_FILE="${CACHE_DIR}/failed-version"
if [ "$(cat "$BAD_FILE" 2>/dev/null)" = "$LATEST" ]; then
  log "Skipping Plex $LATEST (failed earlier; rm $BAD_FILE to retry)."
  exit 0
fi

STREAMS="$("${PLEX_CODE_DIR}/scripts/plex-sessions.sh")"
if [ "${STREAMS:-0}" != "0" ]; then
  log "Plex $LATEST is out (have $CURRENT) but ${STREAMS} stream(s) active; trying next hour."
  exit 0
fi

if [ "${DRY_RUN:-0}" = "1" ]; then
  log "DRY_RUN: would update Plex $CURRENT -> $LATEST from $URL"
  exit 0
fi

mkdir -p "$CACHE_DIR"
NEW_DEB="${CACHE_DIR}/plexmediaserver_${LATEST}_amd64.deb"
fetch_deb "$URL" "$SHA1" "$NEW_DEB" || { log "download/checksum failed for $URL"; push "Plex update failed on $HOST" "Download or checksum failed for $LATEST. Still on $CURRENT."; exit 1; }

# Keep the build we're replacing so a bad update can be undone without plex.tv.
OLD_DEB="${CACHE_DIR}/plexmediaserver_${CURRENT}_amd64.deb"
[ -s "$OLD_DEB" ] || curl -fsSL --max-time 600 -o "$OLD_DEB" \
  "https://downloads.plex.tv/plex-media-server-new/${CURRENT}/debian/plexmediaserver_${CURRENT}_amd64.deb" \
  || { rm -f "$OLD_DEB"; log "couldn't fetch rollback copy of $CURRENT; continuing without it"; }

# Last look right before the restart, in case someone pressed play while downloading.
STREAMS="$("${PLEX_CODE_DIR}/scripts/plex-sessions.sh")"
[ "${STREAMS:-0}" = "0" ] || { log "stream started during download; trying next hour."; exit 0; }

log "Updating Plex $CURRENT -> $LATEST ($CHANNEL)."
if install_deb "$NEW_DEB" && plex_healthy; then
  log "Plex $LATEST is up."
  OLD_MAJOR="${CURRENT%%.*}"; NEW_MAJOR="${LATEST%%.*}"
  if [ "$OLD_MAJOR" != "$NEW_MAJOR" ]; then
    push "Plex major version on $HOST: $OLD_MAJOR -> $NEW_MAJOR" "Installed $LATEST (was $CURRENT). Worth a quick check that clients still play."
  fi
else
  log "Plex $LATEST failed to install or start; rolling back to $CURRENT."
  if [ -s "$OLD_DEB" ] && install_deb "$OLD_DEB" && plex_healthy; then
    log "Rolled back to $CURRENT."
    push "Plex update failed on $HOST" "$LATEST didn't come up, so it was rolled back to $CURRENT. Details: ${LOG_FILE}"
  else
    log "ROLLBACK FAILED; Plex may be down."
    push "Plex DOWN on $HOST after update" "$LATEST failed and rollback to $CURRENT failed. Check ${LOG_FILE} and systemctl status plexmediaserver."
  fi
  echo "$LATEST" > "$BAD_FILE"
  rm -f "$NEW_DEB"
  exit 1
fi

# Tidy: keep only the running build and the one before it.
ls -1t "$CACHE_DIR"/plexmediaserver_*_amd64.deb 2>/dev/null | tail -n +3 | xargs -r rm -f
