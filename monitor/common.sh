#!/bin/bash
# Shared helpers for the off-box monitor scripts (sourced, not run).
# Config: ~/.config/plex-watch.env
#   PLEX_HOST=root@<server>
#   PLEX_SSH_KEY=~/.ssh/plex_monitor   unencrypted key just for these jobs, so they
#                                      work after a reboot (launchd can't unlock a
#                                      Keychain-protected key). See docs/monitor.md.
#   PUSHBULLET_TOKEN=<token>           (preferred) or SLACK_WEBHOOK_URL=...
CONFIG="${PLEX_WATCH_CONFIG:-$HOME/.config/plex-watch.env}"
# shellcheck source=/dev/null
. "$CONFIG"
MONITOR_DOC_URL="${MONITOR_DOC_URL:-https://github.com/n8io/plex-server/blob/master/docs/monitor.md}"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
if [ -n "${PLEX_SSH_KEY:-}" ]; then
  SSH_OPTS+=(-i "${PLEX_SSH_KEY/#\~/$HOME}" -o IdentitiesOnly=yes)
fi

plex_ssh() { ssh "${SSH_OPTS[@]}" "$PLEX_HOST" "$@"; }
plex_scp() { scp -q "${SSH_OPTS[@]}" "$@"; }

# notify "<title>" "<reason>"  -> Pushbullet link push (runbook link + reason), else Slack.
# Returns non-zero when the alert couldn't be delivered, so callers can retry next run.
notify() {
  local TITLE="$1" BODY="$2"
  if [ -n "${PUSHBULLET_TOKEN:-}" ]; then
    /usr/bin/python3 -c 'import json,sys; print(json.dumps({"type": "link", "title": sys.argv[1], "body": sys.argv[2], "url": sys.argv[3]}))' \
      "$TITLE" "$BODY" "$MONITOR_DOC_URL" |
      curl -fsS --max-time 20 -X POST -H "Access-Token: ${PUSHBULLET_TOKEN}" -H 'Content-Type: application/json' \
        --data @- https://api.pushbullet.com/v2/pushes >/dev/null
  else
    /usr/bin/python3 -c 'import json,sys; print(json.dumps({"text": "%s: %s\n%s" % tuple(sys.argv[1:4])}))' \
      "$TITLE" "$BODY" "$MONITOR_DOC_URL" |
      curl -fsS --max-time 20 -X POST -H 'Content-Type: application/json' --data @- "$SLACK_WEBHOOK_URL" >/dev/null
  fi
}
