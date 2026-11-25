# Off-box monitor (n8mini)

Three launchd jobs on n8mini watch the Plex server from outside
(`monitor/install-macos.sh`). Config: `~/.config/plex-watch.env` (chmod 600).

| Job | When | Alerts on |
| --- | --- | --- |
| `io.n8.plex-uptime` (`plex-uptime.sh`) | every 5 min | media mounts unreadable, or the monitor can't SSH in, **3 runs in a row** (15 min); one push on problem, one on recovery |
| `io.n8.plex-backup` (`pull-backup.sh`) | 04:30 local | the night's backup couldn't be copied (says *why*: SSH refused vs no backup on the server); retries for ~10 min first |
| `io.n8.plex-watch` (`plex-watch.sh`) | 10:05 local | updates/disks/backups/drift problems from `scripts/update-status.sh` |

Plex reachability from the internet is **not** checked here. That's Gatus
(uptime.n8io.com) + `plex-client-check` (docs/plex-client-check.md), the single
source of outage alerts, with its own blip protection.

Pushes go to Pushbullet (`PUSHBULLET_TOKEN`) as link pushes to this page, with
the reason in the body; Slack (`SLACK_WEBHOOK_URL`) only if there's no token.
If a push can't be sent, the state isn't saved, so it is retried next run.

## Config

```sh
PLEX_HOST=root@15.235.114.39
PLEX_SSH_KEY=~/.ssh/plex_monitor
PUSHBULLET_TOKEN=...
```

`PLEX_SSH_KEY` is an unencrypted key used only by these jobs. The jobs run with
`BatchMode=yes` under launchd: a Keychain-protected key (`UseKeychain yes`,
`AddKeysToAgent yes`) isn't in ssh-agent after a reboot until someone runs ssh
by hand, so every job failed until then. On the server it is installed as
`restrict ssh-ed25519 ... plex-monitor@n8mini` (no pty or forwarding).
`install-macos.sh` creates the key if it's missing and prints that line.

## Install / update

```sh
cd ~/code/n8io/plex-server && git pull && ./monitor/install-macos.sh
```

Logs: `~/Library/Logs/io.n8.plex-*.log`; uptime state: `~/.cache/plex-uptime/`.

## History

2026-11-25: Nightly "couldn't SSH in" / "no backup found" alerts were the
monitor, not Plex (box up since Nov 13, backups present). Causes: n8mini
rebooted Nov 22 and its Keychain key wasn't loaded (15 hours of refused logins),
a few minutes of n8mini's own internet dropping, and one sub-minute
AT&T→OVH path drop (Nov 25 03:05 ET, SYNs unanswered; 5 min before and after
fine). Also `plex-watch.sh` had been failing on macOS bash 3.2 (heredoc inside
`$(...)`); its Python now lives in `plex-watch-check.py`. The uptime job's
port-32400 check was dropped as a duplicate of Gatus.
