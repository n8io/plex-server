#!/bin/bash
# Runs off-box every 5 minutes (launchd). Checks that the media mounts on the
# Plex server are readable and alerts only when that changes (problem, then
# recovered), and only after FAIL_RUNS checks in a row, so a short network
# drop between this machine and OVH doesn't page anyone.
#
# Plex being reachable from the internet is Gatus's job (uptime.n8io.com +
# plex-client-check), the single source of outage alerts; this script doesn't
# duplicate it. PLEX_EXPECTED=0 silences it while Plex is intentionally off.
set -u
. "$(cd "$(dirname "$0")" && pwd)/common.sh"
[ "${PLEX_EXPECTED:-1}" = "1" ] || exit 0
FAIL_RUNS="${PLEX_UPTIME_FAIL_RUNS:-3}"
STATE_DIR="${HOME}/.cache/plex-uptime"
mkdir -p "$STATE_DIR"

check() {
  local OUT
  OUT="$(plex_ssh 'for d in /mnt/x/decrypted /photos/Workouts; do [ -n "$(timeout 15 find "$d" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ] || echo "$d"; done' 2>&1)" || {
    echo "the monitor on $(hostname -s) couldn't SSH in ($(echo "$OUT" | tail -1 | cut -c1-150))"
    return
  }
  [ -n "$OUT" ] && echo "media not readable: $(echo $OUT)"
}

PROBLEM="$(check)"
if [ -n "$PROBLEM" ]; then
  FAILS=$(( $(cat "$STATE_DIR/fails" 2>/dev/null || echo 0) + 1 ))
else
  FAILS=0
fi
echo "$FAILS" > "$STATE_DIR/fails"

ALERTED="$(cat "$STATE_DIR/alerted" 2>/dev/null || echo 0)"
if [ "$FAILS" -ge "$FAIL_RUNS" ] && [ "$ALERTED" = "0" ]; then
  notify "🚨 Plex server problem" "${PROBLEM} (failing for $((FAILS * 5)) min)" && echo 1 > "$STATE_DIR/alerted"
elif [ "$FAILS" = "0" ] && [ "$ALERTED" = "1" ]; then
  notify "✅ Plex server is back to normal" "Media mounts readable and SSH working again." && echo 0 > "$STATE_DIR/alerted"
fi
exit 0
