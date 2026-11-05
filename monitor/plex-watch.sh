#!/bin/bash
# Runs off-box (on n8mini, via launchd) once a day. Reads scripts/update-status.sh
# on the Plex server over SSH and sends a Slack DM only when something needs
# attention. Silence means the server is up to date.
#
# Config: ~/.config/plex-watch.env (chmod 600)
#   PLEX_HOST=root@<server>
#   PUSHBULLET_TOKEN=<token>       (preferred; same account as Gatus/nzb)
#   SLACK_WEBHOOK_URL=https://hooks.slack.com/...   (used only if no Pushbullet token)
set -u
CONFIG="${PLEX_WATCH_CONFIG:-$HOME/.config/plex-watch.env}"
# shellcheck source=/dev/null
. "$CONFIG"
PLEX_CODE_DIR="${PLEX_CODE_DIR:-/plex-server}"
export PLEX_EXPECTED="${PLEX_EXPECTED:-1}"   # 0 while Plex is intentionally off (before a cutover)

notify() {
  if [ -n "${PUSHBULLET_TOKEN:-}" ]; then
    /usr/bin/python3 -c 'import json,sys; print(json.dumps({"type": "note", "title": "Plex server", "body": sys.argv[1]}))' "${1//:warning: /}" |
      curl -fsS -X POST -H "Access-Token: ${PUSHBULLET_TOKEN}" -H 'Content-Type: application/json' \
        --data @- https://api.pushbullet.com/v2/pushes >/dev/null
  else
    /usr/bin/python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1]}))' "$1" |
      curl -fsS -X POST -H 'Content-Type: application/json' --data @- "$SLACK_WEBHOOK_URL" >/dev/null
  fi
}

STATUS="$(ssh -o BatchMode=yes -o ConnectTimeout=20 "$PLEX_HOST" "${PLEX_CODE_DIR}/scripts/update-status.sh" 2>&1)" || {
  notify ":warning: Plex server ${PLEX_HOST}: can't reach it over SSH (${STATUS:0:200})"
  exit 0
}

PROBLEMS="$(/usr/bin/python3 - "$STATUS" <<'EOF'
import json, os, sys
s = json.loads(sys.argv[1])
now, day = s["now"], 86400
out = []
if now - s["last_update_run"] > 3 * day:
    out.append("automatic updates haven't run in %d days" % ((now - s["last_update_run"]) // day))
# unattended-upgrades installs these nightly; only nag when they've survived ~2 runs.
since = s.get("pending_security_since") or now
if s["pending_security"] > 0 and now - since > 2 * day:
    out.append("%d security update(s) waiting %d days (unattended-upgrades isn't installing them)" % (s["pending_security"], (now - since) // day))
if s["reboot_required_since"] and now - s["reboot_required_since"] > 7 * day:
    out.append("a reboot has been pending for %d days (always busy at 4am?)" % ((now - s["reboot_required_since"]) // day))
if not s["mounts_ok"]:
    out.append("media mounts aren't readable")
if not s["plex_ok"] and os.environ.get("PLEX_EXPECTED", "1") == "1":
    out.append("Plex isn't answering")
if s.get("pro_attached") == "false":
    out.append("Ubuntu Pro isn't attached (no ESM / Livepatch)")
if s.get("raid_ok") is False:
    out.append("a disk mirror is degraded (a drive dropped out)")
if s.get("disks_ok") is False:
    out.append("an NVMe drive reports SMART errors")
if s.get("disk_wear_pct", 0) >= 80:
    out.append("NVMe wear at %d%%; plan a drive swap" % s["disk_wear_pct"])
for k, name in (("root_used_pct", "/"), ("home_used_pct", "/home (cache)")):
    if s.get(k, 0) >= (95 if k == "home_used_pct" else 85):
        out.append("%s is %d%% full" % (name, s[k]))
if s.get("drive_errors", 0) > 20:
    out.append("%d Google Drive auth/quota errors in today's rclone log" % s["drive_errors"])
if s.get("last_backup") is not None and now - s["last_backup"] > 2 * day and os.environ.get("PLEX_EXPECTED", "1") == "1":
    out.append("no good Plex backup in %d days" % ((now - s["last_backup"]) // day))
if s.get("git_dirty"):
    out.append("server setup has local edits not in GitHub (drift)")
if s.get("git_behind"):
    out.append("server isn't on the latest GitHub commit for its branch")
print("\n".join("- " + p for p in out))
EOF
)" || { notify ":warning: Plex server: couldn't read its status: ${STATUS:0:200}"; exit 0; }

[ -n "$PROBLEMS" ] && notify ":warning: Plex server needs a look:
${PROBLEMS}"
exit 0
