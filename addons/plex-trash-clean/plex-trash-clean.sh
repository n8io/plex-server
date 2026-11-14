#!/usr/bin/env bash
# Guarded nightly Plex "Empty Trash".
# Empties a library's trash ONLY when:
#   - the media mount is up and every library root lists non-empty (timeout 30s)
#   - every trashed file is truly absent on disk
#   - trashed < MAX_PCT % of the library and < MAX_ITEMS
# Any section failing a guard is skipped (never partially emptied) and an alert is sent.
#
# What counts as trashed (Plex 1.43 ignores ?trashed=1, so we read deletedAt ourselves):
#   - a whole item (movie / episode) with deletedAt: all of its files
#   - otherwise only the versions (Media / Part) that carry deletedAt.
#     An upgraded episode keeps its live version next to the trashed one; that live
#     file must NOT count as "trashed but still on disk" (2026-11 VisionQuest bug).
#
# Alerts are de-duplicated: the same message is re-sent at most every REALERT_DAYS.
# Config (optional): /etc/plex-trash-clean.env
#   PUSHBULLET_TOKEN=..., MAX_PCT, MAX_ITEMS, DRY_RUN=1, REALERT_DAYS
set -uo pipefail

ENV_FILE=${ENV_FILE:-/etc/plex-trash-clean.env}
[ -r "$ENV_FILE" ] && . "$ENV_FILE"
MOUNT=${MOUNT:-/mnt/x/decrypted}
MAX_PCT=${MAX_PCT:-5}
MAX_ITEMS=${MAX_ITEMS:-200}
DRY_RUN=${DRY_RUN:-0}
REALERT_DAYS=${REALERT_DAYS:-7}
PLEX=${PLEX:-http://127.0.0.1:32400}
PREFS=${PREFS:-"/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml"}
LOG=${LOG:-/var/log/plex-trash-clean.log}
STATE=${STATE:-/var/lib/plex-trash-clean/last-alert}
LOCK=${LOCK:-/run/plex-trash-clean.lock}
exec 9>"$LOCK"; flock -n 9 || exit 0

log(){ echo "$(date -u +%FT%TZ) $*" >>"$LOG"; }
# alert <message> [link]: always logged; pushed unless the identical message went out < REALERT_DAYS ago
alert(){
  local msg=$1 url=${2:-https://app.plex.tv/desktop}
  log "ALERT: $msg"
  local sum; sum=$(printf %s "$msg" | sha256sum | cut -c1-16)
  if [ -r "$STATE" ] && [ "$(cut -d' ' -f1 "$STATE")" = "$sum" ] \
     && [ $(( $(date +%s) - $(cut -d' ' -f2 "$STATE") )) -lt $(( REALERT_DAYS * 86400 )) ]; then
    log "alert suppressed (same as last push, < ${REALERT_DAYS}d ago)"; return 0
  fi
  [ -n "${PUSHBULLET_TOKEN:-}" ] || return 0
  curl -sS -m 15 -H "Access-Token: $PUSHBULLET_TOKEN" -H 'Content-Type: application/json' \
    -d "$(python3 -c 'import json,sys;print(json.dumps({"type":"link","title":"Plex trash cleaner","body":sys.argv[1],"url":sys.argv[2]}))' "$msg" "$url")" \
    https://api.pushbullet.com/v2/pushes >/dev/null \
    && { mkdir -p "$(dirname "$STATE")"; echo "$sum $(date +%s)" >"$STATE"; } \
    || log "pushbullet send failed"
}

TOKEN=$(grep -o 'PlexOnlineToken="[^"]*"' "$PREFS" 2>/dev/null | cut -d'"' -f2)
[ -n "$TOKEN" ] || { alert "No Plex token in Preferences.xml, so nothing was emptied. Check Plex on the box."; exit 1; }
api(){ curl -sS -f -m 120 -H "X-Plex-Token: $TOKEN" -H 'Accept: application/json' "$@"; }

# Guard 1: mount healthy
if ! findmnt -rn "$MOUNT" >/dev/null 2>&1; then
  alert "Media mount $MOUNT is not mounted, so nothing was emptied. Check rclone-media/encfs-media on the box."; exit 1
fi

SECTIONS=$(api "$PLEX/library/sections") || { alert "Plex API unreachable, so nothing was emptied."; exit 1; }
MID=$(api "$PLEX/identity" | python3 -c 'import json,sys;print(json.load(sys.stdin)["MediaContainer"]["machineIdentifier"])' 2>/dev/null || true)
lib_url(){ [ -n "$MID" ] && echo "https://app.plex.tv/desktop/#!/media/$MID/com.plexapp.plugins.library?source=$1" || echo https://app.plex.tv/desktop; }

# Guard 2: every library root lists non-empty
while IFS= read -r root; do
  [ -z "$root" ] && continue
  n=$(timeout 30 ls -A "$root" 2>/dev/null | head -n1 | wc -l)
  [ "$n" -ge 1 ] || { alert "Library folder $root is empty or unreadable (mount problem?), so nothing was emptied."; exit 1; }
done < <(python3 -c 'import json,sys
for d in json.load(sys.stdin)["MediaContainer"].get("Directory",[]):
  for l in d.get("Location",[]): print(l["path"])' <<<"$SECTIONS")

emptied=0; skipped=""; reasons=""; link=""
while IFS=$'\t' read -r id type title; do
  [ -z "$id" ] && continue
  leaf=1; [ "$type" = show ] && leaf=4
  # Line 1: "<total leaf items> <trashed versions>"; then one file path per trashed part.
  out=$(api "$PLEX/library/sections/$id/all?type=$leaf&includeDeleted=1" | python3 -c 'import json,sys
ms=json.load(sys.stdin)["MediaContainer"].get("Metadata",[])
gone=lambda o: bool(o.get("deletedAt"))
n=0; files=[]
for m in ms:
  for md in m.get("Media",[]):
    parts=md.get("Part",[])
    if gone(m) or gone(md):
      n+=1; files+=[p.get("file","") for p in parts]
    else:
      tp=[p for p in parts if gone(p)]
      if tp: n+=1; files+=[p.get("file","") for p in tp]
  if gone(m) and not m.get("Media"): n+=1
print(len(ms), n)
for f in files: print(f)') || { skipped+="$title(API error) "; reasons+="$title: Plex API error while listing trash. "; continue; }
  read -r total ntr <<<"$(head -n1 <<<"$out")"
  files=$(tail -n +2 <<<"$out")
  [ "${ntr:-0}" -eq 0 ] && continue
  # Guard 3: size limits
  if [ "$ntr" -ge "$MAX_ITEMS" ] || [ $(( ntr * 100 )) -ge $(( MAX_PCT * (total>0?total:1) )) ]; then
    skipped+="$title($ntr/$total too many) "
    reasons+="$title: $ntr of $total items are in trash, over the safety limit; review the trash in Plex and empty it by hand if expected. "
    link=${link:-$(lib_url "$id")}; continue
  fi
  # Guard 4: every trashed file truly gone
  present=0; examples=""
  while IFS= read -r f; do
    [ -n "$f" ] && timeout 15 test -e "$f" && { present=$((present+1)); [ "$present" -le 2 ] && examples+=" ${f##*/};"; }
  done <<<"$files"
  if [ "$present" -gt 0 ]; then
    skipped+="$title($present trashed files still on disk; refreshing) "
    reasons+="$title: Plex has $present file(s) in trash that exist on disk (e.g.$examples), so it was not emptied; a rescan was started. If this repeats, check the mount or paths. "
    link=${link:-$(lib_url "$id")}
    [ "$DRY_RUN" = 1 ] || api -X GET "$PLEX/library/sections/$id/refresh" >/dev/null
    continue
  fi
  if [ "$DRY_RUN" = 1 ]; then log "DRY_RUN would empty $title ($ntr/$total)"; continue; fi
  api -X PUT "$PLEX/library/sections/$id/emptyTrash" >/dev/null && { log "emptied $title ($ntr/$total)"; emptied=$((emptied+ntr)); }
done < <(python3 -c 'import json,sys
for d in json.load(sys.stdin)["MediaContainer"].get("Directory",[]): print(d["key"],d["type"],d["title"],sep="\t")' <<<"$SECTIONS")

log "done: emptied=$emptied skipped=[${skipped}] dry_run=$DRY_RUN"
[ -n "$skipped" ] && alert "Skipped: ${reasons% }" "$link"
exit 0
