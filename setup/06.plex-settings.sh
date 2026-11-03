#!/bin/bash
# Plex server settings for media that lives on a cloud mount. Run after Plex is
# claimed (signed in once at http://localhost:32400/web). Safe to re-run; it
# reads every setting back and reports any that didn't stick.
set -e
SCRIPT="$(realpath "$0")"
PLEX_CODE_DIR="$(dirname "$(dirname "$SCRIPT")")"
. "${PLEX_CODE_DIR}/.env"

PLEX_URL="${PLEX_URL:-http://127.0.0.1:32400}"
PLEX_APP_SUPPORT_DIR="${PLEX_APP_SUPPORT_DIR:-/var/lib/plexmediaserver/Library/Application Support}"
PLEX_PREFS="${PLEX_APP_SUPPORT_DIR}/Plex Media Server/Preferences.xml"

# id=value. Comments say why; most exist to stop Plex reading whole files
# from the cloud drive, which is slow and pushes useful titles out of the cache.
SETTINGS=(
  # Thumbnails mean reading every file end to end.
  "GenerateBIFBehavior=never"
  "GenerateChapterThumbBehavior=never"
  # Whole-file analysis jobs: loudness only feeds volume leveling, music
  # analysis has no music library here, ad markers only matter for DVR.
  "LoudnessAnalysisBehavior=never"
  "MusicAnalysisBehavior=never"
  "GenerateAdMarkerBehavior=never"
  # Kept on purpose: intro/credits markers run as episodes arrive (which also
  # pre-caches them) and deep analysis gives true peak bitrates for transcodes.
  "GenerateIntroMarkerBehavior=asap"
  "GenerateCreditsMarkerBehavior=asap"
  "ButlerTaskDeepMediaAnalysis=1"
  # File watching doesn't work on a FUSE mount; scan every 6h as a safety net
  # behind targeted scans (plex-scan.sh / Plex Scan UI).
  "FSEventLibraryUpdatesEnabled=0"
  "ScheduledLibraryUpdatesEnabled=1"
  "ScheduledLibraryUpdateInterval=21600"
  "ScannerLowPriority=1"
  # A mount blip must never empty the library.
  "autoEmptyTrash=0"
  "allowMediaDeletion=0"
  # Transcode into RAM.
  "TranscoderTempDirectory=/dev/shm"
  # Library DB is ~450 MB; the default 40 MB cache makes browsing hit disk.
  "DatabaseCacheSize=1024"
  # Datacenter box: no LAN, no UPnP, direct connections only.
  "DlnaEnabled=0"
  "RelayEnabled=0"
  "ManualPortMappingMode=1"
  "ManualPortMappingPort=32400"
  "sendCrashReports=0"
  "logDebug=0"
)

PLEX_TOKEN="${PLEX_TOKEN:-$(grep -oE 'PlexOnlineToken="[^"]+"' "$PLEX_PREFS" 2>/dev/null | cut -d'"' -f2)}"
if [ -z "$PLEX_TOKEN" ]; then
  echo "No Plex token in ${PLEX_PREFS}. Sign in to Plex at ${PLEX_URL}/web first." >&2
  exit 1
fi

echo "Plex settings updating..."
QUERY=""
for kv in "${SETTINGS[@]}"; do
  QUERY="${QUERY}&$(python3 -c 'import sys,urllib.parse as u; k,v=sys.argv[1].split("=",1); print(u.quote(k)+"="+u.quote(v))' "$kv")"
done
curl -fsS -X PUT -H "X-Plex-Token: ${PLEX_TOKEN}" "${PLEX_URL}/:/prefs?${QUERY#&}" >/dev/null

# Read back and compare. Plex reports booleans as true/false.
PREFS_JSON="$(mktemp)"
curl -fsS -H "X-Plex-Token: ${PLEX_TOKEN}" -H "Accept: application/json" "${PLEX_URL}/:/prefs" -o "$PREFS_JSON"
STATUS=0
python3 - "$PREFS_JSON" "${SETTINGS[@]}" <<'EOF' || STATUS=$?
import json, sys
prefs = {s["id"]: s["value"] for s in json.load(open(sys.argv[1]))["MediaContainer"]["Setting"]}
norm = lambda v: {"true": "1", "false": "0"}.get(str(v).lower(), str(v))
bad = 0
for kv in sys.argv[2:]:
    k, want = kv.split("=", 1)
    got = prefs.get(k)
    if got is None:
        print(f"  ? {k}: not a setting on this Plex version"); bad += 1
    elif norm(got) != norm(want):
        print(f"  x {k}: wanted {want}, Plex has {got}"); bad += 1
print("  All settings applied." if not bad else f"  {bad} setting(s) need a look.")
sys.exit(1 if bad else 0)
EOF
rm -f "$PREFS_JSON"
[ "$STATUS" = "0" ] && echo -e "\e[32mPlex settings updated successfully.\e[0m"
exit "$STATUS"
