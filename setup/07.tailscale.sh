#!/bin/bash
# Tailscale for private admin access: Plex Scan UI is served to the tailnet
# only (https://<node>.<tailnet>.ts.net -> 127.0.0.1:8080). Plex itself stays
# public on 32400.
set -e

TS_HOSTNAME="${TS_HOSTNAME:-n8flix}"
SCAN_UI_PORT="${SCAN_UI_PORT:-8080}"

if ! command -v tailscale >/dev/null 2>&1; then
  echo -n "  Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh >/dev/null
  echo "done."
fi

if ! tailscale status >/dev/null 2>&1; then
  echo "  Sign this node in to your tailnet (opens a login URL):"
  tailscale up --hostname="$TS_HOSTNAME"
fi

echo -n "  Serving Plex Scan UI on the tailnet..."
tailscale serve --bg "http://127.0.0.1:${SCAN_UI_PORT}" >/dev/null
echo "done."
tailscale serve status
echo -e "\e[32mTailscale set up successfully.\e[0m"
