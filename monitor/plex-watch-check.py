#!/usr/bin/env python3
# Turns scripts/update-status.sh's JSON (argv[1]) into a list of problems.
# Kept out of plex-watch.sh: macOS's bash 3.2 can't parse a heredoc with
# quotes/parens inside $(...), which broke the daily check.
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
