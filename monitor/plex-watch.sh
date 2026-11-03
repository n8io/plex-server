#!/bin/bash
# Runs off-box (on n8mini, via launchd) once a day. Reads scripts/update-status.sh
# on the Plex server over SSH and sends a Slack DM only when something needs
# attention. Silence means the server is up to date.
#
# Config: ~/.config/plex-watch.env (chmod 600)
#   PLEX_HOST=root@<server>        SLACK_WEBHOOK_URL=https://hooks.slack.com/...
set -u
CONFIG="${PLEX_WATCH_CONFIG:-$HOME/.config/plex-watch.env}"
# shellcheck source=/dev/null
. "$CONFIG"
PLEX_CODE_DIR="${PLEX_CODE_DIR:-/plex-server}"

notify() {
  /usr/bin/python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1]}))' "$1" |
    curl -fsS -X POST -H 'Content-Type: application/json' --data @- "$SLACK_WEBHOOK_URL" >/dev/null
}

STATUS="$(ssh -o BatchMode=yes -o ConnectTimeout=20 "$PLEX_HOST" "${PLEX_CODE_DIR}/scripts/update-status.sh" 2>&1)" || {
  notify ":warning: Plex server ${PLEX_HOST}: can't reach it over SSH (${STATUS:0:200})"
  exit 0
}

PROBLEMS="$(/usr/bin/python3 - "$STATUS" <<'EOF'
import json, sys
s = json.loads(sys.argv[1])
now, day = s["now"], 86400
out = []
if now - s["last_update_run"] > 3 * day:
    out.append("automatic updates haven't run in %d days" % ((now - s["last_update_run"]) // day))
if s["pending_security"] > 0:
    out.append("%d security update(s) waiting" % s["pending_security"])
if s["reboot_required_since"] and now - s["reboot_required_since"] > 7 * day:
    out.append("a reboot has been pending for %d days (always busy at 4am?)" % ((now - s["reboot_required_since"]) // day))
if not s["mounts_ok"]:
    out.append("media mounts aren't readable")
if not s["plex_ok"]:
    out.append("Plex isn't answering")
if s.get("pro_attached") == "false":
    out.append("Ubuntu Pro isn't attached (no ESM / Livepatch)")
print("\n".join("- " + p for p in out))
EOF
)" || { notify ":warning: Plex server: couldn't read its status: ${STATUS:0:200}"; exit 0; }

[ -n "$PROBLEMS" ] && notify ":warning: Plex server needs a look:
${PROBLEMS}"
exit 0
