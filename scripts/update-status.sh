#!/bin/bash
# One line of JSON describing how healthy and up to date this box is. The
# watchers on another machine (monitor/plex-watch.sh, monitor/plex-uptime.sh)
# read it over SSH and alert.
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env" >/dev/null 2>&1

NOW="$(date +%s)"
LAST_RUN="$(stat -c %Y /var/lib/apt/periodic/unattended-upgrades-stamp 2>/dev/null || echo 0)"

# Security updates still waiting (unattended-upgrades would have installed them).
PENDING="$(apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null | grep -c '^Inst .*-security')"
# When they first showed up. New fixes land between nightly runs, so the watcher
# only cares about ones that survived a run or two, not ones published this morning.
PENDING_STATE=/var/lib/plex-server/security-pending-since
if [ "${PENDING:-0}" -gt 0 ]; then
  [ -s "$PENDING_STATE" ] || { mkdir -p "$(dirname "$PENDING_STATE")"; echo "$NOW" > "$PENDING_STATE"; }
  PENDING_SINCE="$(cat "$PENDING_STATE" 2>/dev/null || echo "$NOW")"
else
  rm -f "$PENDING_STATE"; PENDING_SINCE=0
fi

REBOOT_SINCE=0
[ -f /var/run/reboot-required ] && REBOOT_SINCE="$(stat -c %Y /var/run/reboot-required)"

MOUNTS_OK=true
for d in "${DEC_DIR_LOCAL:-/mnt/x/decrypted}" "${PHOTOS_DIR_LOCAL:-/photos/Workouts}"; do
  [ -n "$(timeout 20 find "$d" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ] || MOUNTS_OK=false
done

PLEX_OK=false
curl -fsS --max-time 10 http://127.0.0.1:32400/identity >/dev/null 2>&1 && PLEX_OK=true

LIVEPATCH="$(canonical-livepatch status 2>/dev/null | grep -m1 -oE 'running: (true|false)' | cut -d' ' -f2)"
PRO="$(pro status --format json 2>/dev/null | grep -oE '"attached": (true|false)' | cut -d' ' -f2)"

# Disks: a degraded mirror shows "_" in mdstat's [UU]; NVMe health from SMART.
RAID_OK=true
grep -E '^\s+[0-9]+ blocks.*\[[U_]+\]' /proc/mdstat | grep -q '_' && RAID_OK=false
DISK_WORST=0; DISK_OK=true
for n in /dev/nvme[0-9]n1; do
  [ -e "$n" ] || continue
  read -r PASSED USED WARN ERRS <<<"$(smartctl -j -H -A "$n" 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin); l=d.get("nvme_smart_health_information_log",{})
print(d.get("smart_status",{}).get("passed",False), l.get("percentage_used",0), l.get("critical_warning",0), l.get("media_errors",0))' 2>/dev/null)"
  [ "${USED:-0}" -gt "$DISK_WORST" ] && DISK_WORST="$USED"
  { [ "$PASSED" != "True" ] || [ "${WARN:-0}" != "0" ] || [ "${ERRS:-0}" != "0" ]; } && DISK_OK=false
done
ROOT_PCT="$(df --output=pcent / | tail -1 | tr -dc 0-9)"
HOME_PCT="$(df --output=pcent /home | tail -1 | tr -dc 0-9)"

# Google Drive: auth or quota errors in today's rclone log.
DRIVE_ERRORS="$(grep -cE 'invalid_grant|unauthorized|quota|rateLimitExceeded|403 Forbidden|401' "${PLEX_CODE_DIR}/logs/rclone-media.log" 2>/dev/null || true)"

LAST_BACKUP="$(cat /var/backups/plex/last-success 2>/dev/null || echo 0)"

# Drift: local edits, or not on the commit GitHub has for this branch.
GIT_DIRTY=false; GIT_BEHIND=false
if cd "$PLEX_CODE_DIR" 2>/dev/null && git rev-parse >/dev/null 2>&1; then
  [ -n "$(git status --porcelain --untracked-files=no)" ] && GIT_DIRTY=true
  if timeout 20 git fetch -q origin 2>/dev/null; then
    UP="$(git rev-parse '@{u}' 2>/dev/null)"
    [ -n "$UP" ] && [ "$(git rev-parse HEAD)" != "$UP" ] && GIT_BEHIND=true
  fi
fi

printf '{"now":%s,"last_update_run":%s,"pending_security":%s,"pending_security_since":%s,"reboot_required_since":%s,"mounts_ok":%s,"plex_ok":%s,"livepatch":"%s","pro_attached":"%s","release":"%s","raid_ok":%s,"disks_ok":%s,"disk_wear_pct":%s,"root_used_pct":%s,"home_used_pct":%s,"drive_errors":%s,"last_backup":%s,"git_dirty":%s,"git_behind":%s}\n' \
  "$NOW" "$LAST_RUN" "${PENDING:-0}" "${PENDING_SINCE:-0}" "$REBOOT_SINCE" "$MOUNTS_OK" "$PLEX_OK" \
  "${LIVEPATCH:-unknown}" "${PRO:-unknown}" "$(lsb_release -rs 2>/dev/null)" \
  "$RAID_OK" "$DISK_OK" "${DISK_WORST:-0}" "${ROOT_PCT:-0}" "${HOME_PCT:-0}" "${DRIVE_ERRORS:-0}" "$LAST_BACKUP" "$GIT_DIRTY" "$GIT_BEHIND"
