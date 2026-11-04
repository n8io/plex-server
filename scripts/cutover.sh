#!/bin/bash
# Move Plex from the old box to this one, unattended, all-or-nothing.
#
#   cutover.sh --dry-run   every check and the data sync, but Plex never moves
#   cutover.sh             the real thing
#
# Runs on the NEW box. Needs root SSH to the old box (OLD), and a Slack webhook
# in /root/.config/plex-cutover.env (SLACK_WEBHOOK_URL=...).
#
# The old box is only ever read from, and its Plex is only stopped/started.
# Any failed check after the old Plex stops rolls back: new Plex off, old Plex
# on, exactly as before. The outcome is DMed either way.
set -uo pipefail

OLD="${OLD:-root@158.69.124.112}"
NEW_IP="${NEW_IP:-15.235.114.39}"
PMS="/var/lib/plexmediaserver/Library/Application Support/Plex Media Server"
SQLITE="/usr/lib/plexmediaserver/Plex SQLite"
LOG=/root/cutover.log
WAIT_IDLE_MIN="${WAIT_IDLE_MIN:-60}"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
# --test-rollback: run only the rollback path while the old Plex is still up
# (new Plex off + old Plex start are both no-ops then), to prove it works.
TEST_ROLLBACK=0; [ "${1:-}" = "--test-rollback" ] && TEST_ROLLBACK=1
# shellcheck source=/dev/null
. /root/.config/plex-cutover.env

exec > >(tee -a "$LOG") 2>&1
say() { echo "$(date -u +%T) $*"; }
dm() {
  python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1]}))' "$1" > /root/.cutover-msg.json
  curl -fsS -X POST -H 'Content-Type: application/json' --data @/root/.cutover-msg.json "$SLACK_WEBHOOK_URL" >/dev/null || true
}
oldssh() { ssh -o BatchMode=yes -o ConnectTimeout=20 "$OLD" "$@"; }
token_old() { oldssh "grep -oE 'PlexOnlineToken=\"[^\"]+\"' \"$PMS/Preferences.xml\" | cut -d'\"' -f2"; }
# GET a Plex path on the old or new box; prints the body.
plex_old() { oldssh "curl -fsS --max-time 20 -H 'Accept: application/json' -H 'X-Plex-Token: $TOKEN' 'http://127.0.0.1:32400$1'"; }
plex_new() { curl -fsS --max-time 20 -H 'Accept: application/json' -H "X-Plex-Token: $TOKEN" "http://127.0.0.1:32400$1"; }
jq_py() { python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

# Library fingerprint: section count and item count per section.
fingerprint() {  # $1 = old|new
  local f="plex_$1" out="" keys
  keys="$($f /library/sections | jq_py 'print(" ".join(s["key"] for s in d["MediaContainer"].get("Directory",[])))')" || return 1
  for k in $keys; do
    out="$out $k=$($f "/library/sections/$k/all?X-Plex-Container-Start=0&X-Plex-Container-Size=0" | jq_py 'print(d["MediaContainer"].get("totalSize", d["MediaContainer"].get("size")))')"
  done
  echo "$out"
}

FAILED=""
fail() { FAILED="$1"; say "FAIL: $1"; }

rollback() {
  STAGE=rolling
  say "Rolling back: new Plex off, old Plex on."
  systemctl disable --now plexmediaserver >/dev/null 2>&1
  oldssh 'systemctl start plexmediaserver' ; sleep 20
  if oldssh 'curl -fsS --max-time 10 http://127.0.0.1:32400/identity' >/dev/null 2>&1; then
    dm ":leftwards_arrow_with_hook: Plex cutover rolled back: ${FAILED}. The old server is serving again, exactly as before. Nothing else changed."
  else
    dm ":rotating_light: Plex cutover rolled back (${FAILED}) but the OLD Plex isn't answering yet. Check: ssh ${OLD} systemctl status plexmediaserver"
  fi
  exit 1
}

say "=== cutover $( [ $DRY = 1 ] && echo DRY RUN ) ==="
if [ $TEST_ROLLBACK = 1 ]; then
  systemctl is-active --quiet plexmediaserver && { echo "new Plex is running; not a safe time to test rollback" >&2; exit 2; }
  FAILED="ROLLBACK TEST (nothing was switched)"; rollback
fi

# ---- 1. pre-checks: nothing has changed yet, so a failure just stops -------
oldssh true || { dm ":warning: Plex cutover didn't start: can't SSH to the old server. Nothing changed."; exit 1; }
TOKEN="$(token_old)"; [ -n "$TOKEN" ] || { dm ":warning: Plex cutover didn't start: no Plex token on the old server. Nothing changed."; exit 1; }
oldssh 'systemctl is-active --quiet plexmediaserver' || { dm ":warning: Plex cutover didn't start: old Plex isn't running. Nothing changed."; exit 1; }
OLD_ID="$(plex_old /identity | jq_py 'print(d["MediaContainer"]["machineIdentifier"])')"
say "old server id: $OLD_ID"
systemctl is-active --quiet plexmediaserver && { dm ":warning: Plex cutover didn't start: Plex is already running on the new server. Nothing changed."; exit 1; }
"$(dirname "$(realpath "$0")")/update-status.sh" > /root/.cutover-status.json
python3 - /root/.cutover-status.json <<'EOF' || { dm ":warning: Plex cutover didn't start: new server pre-check failed ($(cat /root/.cutover-status.json)). Nothing changed."; exit 1; }
import json, sys
s = json.load(open(sys.argv[1]))
bad = [k for k in ("mounts_ok", "raid_ok", "disks_ok") if s.get(k) is not True]
if s.get("root_used_pct", 0) > 80: bad.append("root disk full")
print("new server checks:", "ok" if not bad else bad); sys.exit(1 if bad else 0)
EOF

# Wait for nobody to be watching (up to WAIT_IDLE_MIN).
for i in $(seq 1 $((WAIT_IDLE_MIN / 2 + 1))); do
  N="$(plex_old /status/sessions | jq_py 'print(d["MediaContainer"].get("size",0))')"
  [ "${N:-1}" = "0" ] && break
  say "$N stream(s) active; waiting"; [ $DRY = 1 ] && break; sleep 120
done
[ "${N:-1}" = "0" ] || { [ $DRY = 1 ] || { dm ":warning: Plex cutover skipped: people were still watching after ${WAIT_IDLE_MIN} min. Nothing changed; I'll need a new time."; exit 1; }; }
say "streams on old: $N"

OLD_FP="$(fingerprint old)" || { dm ":warning: Plex cutover didn't start: couldn't read the old library. Nothing changed."; exit 1; }
say "old libraries:$OLD_FP"
curl -fsS --max-time 15 https://plex.tv/api/v2/ping -H "X-Plex-Token: $TOKEN" -H 'X-Plex-Client-Identifier: n8flix-cutover' >/dev/null || { dm ":warning: Plex cutover didn't start: plex.tv unreachable. Nothing changed."; exit 1; }

# ---- 2. switch ------------------------------------------------------------
if [ $DRY = 0 ]; then
  # From here until success, ANY exit (a crash, a kill, a bug) rolls back.
  STAGE=switching
  trap '[ "${STAGE:-}" = switching ] && { STAGE=rolling; FAILED="${FAILED:-cutover script stopped unexpectedly}"; rollback; }' EXIT
  dm ":arrows_counterclockwise: Plex cutover starting (nobody watching). Plex will be down ~10 min."
  say "stopping old Plex"
  oldssh 'systemctl stop plexmediaserver' || { FAILED="couldn't stop old Plex"; rollback; }
fi
SYNC_START=$(date +%s)
rsync -aHL --delete-after -e "ssh -o BatchMode=yes" \
  --exclude="Cache/" --exclude="Logs/" --exclude="Crash Reports/" --exclude="Codecs/" \
  --exclude="*-shm" --exclude="*-wal" --exclude="com.plexapp.plugins.library*.db-20*" \
  --exclude="Plug-in Support/Databases/pre-restore-*" \
  "$OLD:$PMS/" "$PMS/" || { FAILED="final data sync failed"; [ $DRY = 1 ] && { dm ":x: Plex cutover DRY RUN failed: $FAILED"; exit 1; }; rollback; }
chown -R plex:plex /var/lib/plexmediaserver
say "final sync took $(( $(date +%s) - SYNC_START ))s"

for db in com.plexapp.plugins.library.db com.plexapp.plugins.library.blobs.db; do
  R="$("$SQLITE" "$PMS/Plug-in Support/Databases/$db" 'PRAGMA integrity_check;' | head -1)"
  say "integrity $db: $R"
  [ "$R" = "ok" ] || { FAILED="copied database $db failed integrity check"; [ $DRY = 1 ] && { dm ":x: Plex cutover DRY RUN: $FAILED (on a live copy this can be a false alarm; real run copies after a clean stop)"; exit 1; }; rollback; }
done
NEW_PREF_ID="$(grep -oE 'ProcessedMachineIdentifier="[^"]+"' "$PMS/Preferences.xml" | cut -d'"' -f2)"
say "identity in copied Preferences: $NEW_PREF_ID"

if [ $DRY = 1 ]; then
  dm ":white_check_mark: Plex cutover DRY RUN passed. Old server reachable, $N stream(s), libraries:${OLD_FP}. New server mounts/RAID/disks OK. Final sync $(( $(date +%s) - SYNC_START ))s, databases pass integrity check. Nothing was switched."
  say "dry run passed"; exit 0
fi

# ---- 3. start the new Plex and prove it -------------------------------------
systemctl enable --now plexmediaserver >/dev/null 2>&1
for i in $(seq 1 36); do curl -fsS --max-time 5 http://127.0.0.1:32400/identity >/dev/null 2>&1 && break; sleep 5; done
NEW_ID="$(plex_new /identity | jq_py 'print(d["MediaContainer"]["machineIdentifier"])')" || NEW_ID=""
[ "$NEW_ID" = "$OLD_ID" ] || { fail "new Plex identity '$NEW_ID' != old '$OLD_ID'"; rollback; }

NEW_FP="$(fingerprint new)" || NEW_FP=""
say "new libraries:$NEW_FP"
[ "$NEW_FP" = "$OLD_FP" ] || { fail "library counts differ (old:$OLD_FP new:$NEW_FP)"; rollback; }

# A real file through Plex: first MB of a random movie part.
PART="$(plex_new "/library/recentlyAdded?X-Plex-Container-Start=0&X-Plex-Container-Size=50" | jq_py '
import random
items=[m for m in d["MediaContainer"].get("Metadata",[]) if m.get("Media")]
m=random.choice(items); print(m["Media"][0]["Part"][0]["key"])')" || PART=""
BYTES="$(curl -fsS --max-time 60 -r 0-1048575 -H "X-Plex-Token: $TOKEN" "http://127.0.0.1:32400${PART}" | wc -c)"
say "playback test $PART: $BYTES bytes"
[ "${BYTES:-0}" -ge 1000000 ] || { fail "test playback read only ${BYTES:-0} bytes"; rollback; }

curl -fsS --max-time 15 "http://${NEW_IP}:32400/identity" >/dev/null || { fail "not reachable on public IP ${NEW_IP}:32400"; rollback; }

# plex.tv should list this server at the new IP (it can take a few minutes).
SEEN=0
for i in $(seq 1 20); do
  if curl -fsS --max-time 15 -H 'Accept: application/json' -H "X-Plex-Token: $TOKEN" -H 'X-Plex-Client-Identifier: n8flix-cutover' \
       "https://plex.tv/api/v2/resources?includeHttps=1" | OLD_ID="$OLD_ID" NEW_IP="$NEW_IP" python3 -c '
import json,os,sys
for r in json.load(sys.stdin):
    if r.get("clientIdentifier")==os.environ["OLD_ID"] and any(c.get("address")==os.environ["NEW_IP"] for c in r.get("connections",[])): sys.exit(0)
sys.exit(1)'; then SEEN=1; break; fi
  sleep 30
done
[ $SEEN = 1 ] || { fail "plex.tv still doesn't list N8Flix at ${NEW_IP} after 10 min"; rollback; }

# ---- 4. success: keep the old Plex from ever starting again -----------------
STAGE=done
oldssh 'systemctl disable plexmediaserver' >/dev/null 2>&1
"$(dirname "$(realpath "$0")")/../setup/06.plex-settings.sh" || say "settings script reported issues (non-fatal)"
dm ":tada: Plex cutover done. N8Flix now runs on the new server (${NEW_IP}); same identity, libraries match (${NEW_FP}), test playback OK, plex.tv sees it. Old Plex is stopped and disabled (box kept as fallback). Morning to-dos: plex.n8io.com DNS, nzb2 scan target."
say "cutover complete"
