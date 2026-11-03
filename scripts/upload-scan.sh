#!/usr/bin/env bash
# Plex box: targeted Plex scans for folders nzb2 just uploaded.
#
# nzb2 runs:  printf '%s\n' "movies/release/X (2024)/X.mkv" | ssh -i KEY root@PLEX upload-scan
# (forced command in authorized_keys, so nzb2 can't run anything else).
#
# Reads file paths relative to DEC_DIR (one per line) on stdin, queues them,
# and returns at once. A detached worker waits until each file is visible on
# the rclone/encfs mount, then calls Plex's partial scan for just the folder
# holding it, in the library whose location contains it.
#
#   upload-scan.sh            enqueue from stdin, start worker (what SSH runs)
#   upload-scan.sh --worker   process the queue (started automatically)
set -euo pipefail

DEC_DIR="${DEC_DIR:-/mnt/x/decrypted}"
PLEX_URL="${PLEX_URL:-http://127.0.0.1:32400}"
PREFS="${PLEX_PREFS:-/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml}"
STATE="${STATE_DIR:-/var/lib/upload-scan}"
LOG="${LOG_FILE:-/var/log/upload-scan.log}"
WAIT_SECS="${WAIT_SECS:-900}"     # give up on a file after 15 min
POLL_SECS="${POLL_SECS:-10}"
SELF="$(realpath "$0")"

mkdir -p "$STATE/queue"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# ---- enqueue (SSH entry point) -------------------------------------------
if [[ "${1:-}" != "--worker" ]]; then
  q="$STATE/queue/$(date +%s).$$"
  n=0
  while IFS= read -r rel || [[ -n "$rel" ]]; do
    rel="${rel#/}"; rel="${rel%/}"
    # Only plain relative paths inside DEC_DIR; no traversal, no control chars.
    [[ -z "$rel" || "/$rel/" == */../* || "$rel" =~ [[:cntrl:]] ]] && { log "reject: $(printf %q "$rel")"; continue; }
    printf '%s\t%s\n' "$(date +%s)" "$rel" >> "$q.tmp"; n=$((n+1))
  done
  [[ -f "$q.tmp" ]] && mv "$q.tmp" "$q"
  log "queued $n file(s)"
  setsid nohup "$SELF" --worker </dev/null >/dev/null 2>&1 &
  echo "queued $n"
  exit 0
fi

# ---- worker ---------------------------------------------------------------
exec 9>"$STATE/worker.lock"
flock -n 9 || exit 0   # one worker; it picks up anything queued while running

TOKEN="${PLEX_TOKEN:-$(grep -oE 'PlexOnlineToken="[^"]+"' "$PREFS" | cut -d'"' -f2)}"
[[ -n "$TOKEN" ]] || { log "error: no Plex token in $PREFS"; exit 1; }

# "<section id>\t<location path>" for every library location, longest first.
sections() {
  curl -fsS -H "X-Plex-Token: $TOKEN" "$PLEX_URL/library/sections" | python3 -c '
import sys, xml.etree.ElementTree as ET
rows = [(d.get("key"), l.get("path").rstrip("/")) for d in ET.parse(sys.stdin).getroot().iter("Directory") for l in d.iter("Location")]
for k, p in sorted(rows, key=lambda r: -len(r[1])): print(k + "\t" + p)'
}

while :; do
  shopt -s nullglob; files=("$STATE"/queue/*[0-9]); shopt -u nullglob
  pending="$STATE/pending"; : > "$pending.new"
  [[ -f "$pending" ]] && cat "$pending" >> "$pending.new"
  for f in ${files[@]+"${files[@]}"}; do cat "$f" >> "$pending.new"; rm -f "$f"; done
  # de-dupe by file, keep earliest enqueue time
  LC_ALL=C sort -t$'\t' -k2,2 -k1,1n "$pending.new" | awk -F'\t' '!seen[$2]++' > "$pending"
  rm -f "$pending.new"
  if [[ ! -s "$pending" ]]; then
    rm -f "$pending"; flock -u 9
    # something queued between our last look and the unlock? run again
    compgen -G "$STATE/queue/*[0-9]" >/dev/null && exec "$SELF" --worker
    exit 0
  fi

  map="$(sections)" || { log "error: Plex not answering, retry in 60s"; sleep 60; continue; }
  now=$(date +%s); : > "$pending.keep"; : > "$STATE/ready"
  while IFS=$'\t' read -r ts rel; do
    if [[ -e "$DEC_DIR/$rel" ]]; then
      printf '%s\t%s\n' "$ts" "$rel" >> "$STATE/ready"
    elif (( now - ts > WAIT_SECS )); then log "give up (never appeared): $rel"
    else printf '%s\t%s\n' "$ts" "$rel" >> "$pending.keep"; fi
  done < "$pending"
  # one scan per folder holding visible files
  declare -A waited=()
  while IFS=$'\t' read -r ts rel; do
    d="$(dirname "$DEC_DIR/$rel")"; w=$((now - ts))
    (( ${waited[$d]:--1} >= w )) || waited[$d]=$w
  done < "$STATE/ready"
  for abs in ${waited[@]+"${!waited[@]}"}; do
    rel="${abs#"$DEC_DIR"/}"
    id=""; while IFS=$'\t' read -r k loc; do
      [[ "$abs" == "$loc" || "$abs" == "$loc/"* ]] && { id="$k"; break; }
    done <<< "$map"
    if [[ -z "$id" ]]; then log "skip (no library holds it): $rel"; continue; fi
    enc="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$abs")"
    if curl -fsS -o /dev/null -H "X-Plex-Token: $TOKEN" \
         "$PLEX_URL/library/sections/$id/refresh?path=$enc"; then
      log "scan: section $id $rel (waited ${waited[$abs]}s)"
    else
      log "error: scan failed, will retry: $rel"
      awk -F'\t' -v d="$abs" -v root="$DEC_DIR" '{ f=root "/" $2; sub(/\/[^\/]*$/, "", f) } f==d' "$STATE/ready" >> "$pending.keep"
    fi
  done
  unset waited
  mv "$pending.keep" "$pending"
  sleep "$POLL_SECS"
done
