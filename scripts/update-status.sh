#!/bin/bash
# One line of JSON describing how up to date this box is. The watcher on
# another machine (monitor/plex-watch.sh) reads it over SSH and alerts.
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env" >/dev/null 2>&1

NOW="$(date +%s)"
STAMP="/var/lib/apt/periodic/unattended-upgrades-stamp"
LAST_RUN="$(stat -c %Y "$STAMP" 2>/dev/null || echo 0)"

# Security updates still waiting (unattended-upgrades would have installed them).
PENDING="$(apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null | grep -c '^Inst .*-security')"

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

printf '{"now":%s,"last_update_run":%s,"pending_security":%s,"reboot_required_since":%s,"mounts_ok":%s,"plex_ok":%s,"livepatch":"%s","pro_attached":"%s","release":"%s"}\n' \
  "$NOW" "$LAST_RUN" "${PENDING:-0}" "$REBOOT_SINCE" "$MOUNTS_OK" "$PLEX_OK" \
  "${LIVEPATCH:-unknown}" "${PRO:-unknown}" "$(lsb_release -rs 2>/dev/null)"
