# Plex client-view check

`monitor/plex-client-check.py` checks Plex the way a phone or TV app sees it, and reports to Gatus. Gatus (uptime.n8io.com on the Coolify VPS) is still the only alert sender, via Pushbullet.

## Why it exists

On 2026-11-08 every Plex app blocked N8Flix with "Server is Outdated (needs 1.41.2+)". Plex itself was up and on 1.43.5, so the Gatus `/identity` check stayed green. Tautulli on the Plex box was signed in with the server's own `PlexOnlineToken`. Each Tautulli call to plex.tv rewrote the server's device record with Tautulli's name and version (`ns5018135 (Tautulli)`, `v2.18.2`). Apps trust plex.tv's record, not the server.

What monitoring covered before, and why none of it saw this:

| Check | Looks at | Missed it because |
|---|---|---|
| Gatus `Plex` | `http://plex.n8io.com:32400/identity` returns 200 | The server was fine. Only plex.tv's record was wrong. |
| plex-watch (n8mini, daily) | box health over SSH | Never asks plex.tv anything |

## What it checks (every 2 min, from the VPS)

Two Gatus external endpoints in group **Media Management**:

**Plex app view** (`media-management_plex-app-view`): plex.tv's record for the server (`/api/v2/resources`, by `SERVER_ID`)
- exists on the account, owned, `provides` server, `presence` true
- product is `Plex Media Server` and name is `SERVER_NAME` (a different name/product means some other app is using the server's token)
- version is 1.x, at least `MIN_VERSION`, and equal to what the server itself reports over the remote connection
- no second owned server with the same name (old box or an impostor)
- plex.tv unreachable or the checker's token rejected also fails here

**Plex remote access** (`media-management_plex-remote-access`): the remote connections plex.tv hands to apps (non-local, non-relay; IPv4 first). One must answer `/identity` with our `machineIdentifier` and list libraries at `/library/sections` using the access token apps get.

Both endpoints have a heartbeat, so a dead timer or broken checker alerts too.

## Deployment (VPS 147.93.119.166, `ssh tgl-prod` from n8m1)

```
/opt/plex-client-check/plex-client-check.py     # copy of monitor/plex-client-check.py
/etc/systemd/system/plex-client-check.{service,timer}
/etc/plex-client-check.env                     # root:root 600
```

`/etc/plex-client-check.env`:

```
SERVER_ID=73529840dfee9467042ba1fe881a3d464fc7852c   # N8Flix clientIdentifier
SERVER_NAME=N8Flix
MIN_VERSION=1.41.2           # raise when apps start asking for newer
GATUS_URL=https://uptime.n8io.com
GATUS_TOKEN=...              # same value as Gatus env PLEX_CLIENT_CHECK_TOKEN
PLEX_TOKEN=...               # written by --link
PLEX_CLIENT_ID=n8io-plex-client-check
```

The checker has **its own plex.tv device token**. Never give it, Tautulli, or anything else the server's `PlexOnlineToken`: that is exactly what broke things. To (re)create the token:

```
sudo PLEX_CLIENT_CHECK_ENV=/etc/plex-client-check.env python3 /opt/plex-client-check/plex-client-check.py --link
# enter the printed code at https://plex.tv/link while signed in as the server owner
```

Gatus side (Coolify → uptime.n8io.com service; config on the VPS at `/data/coolify/services/ukoookc88skco4sk8cwos8cc/config.yaml`, bind-mounted to `/config/config.yaml`; env var `PLEX_CLIENT_CHECK_TOKEN` is a Coolify env var on that service, same value as `GATUS_TOKEN` above). External endpoints have no URL, so each alert overrides the Pushbullet body to send a **link push** to its Gatus page. `[RESULT_ERRORS]` carries the checker's reason (blank on UP).

```yaml
external-endpoints:
  - name: Plex app view
    group: Media Management
    token: "${PLEX_CLIENT_CHECK_TOKEN}"
    heartbeat:
      interval: 10m          # no push for 10 min = checker is dead = alert
    alerts:
      - type: custom
        failure-threshold: 2
        success-threshold: 2
        send-on-resolved: true
        description: "Plex apps may block N8Flix: plex.tv's record of the server looks wrong"
        provider-override:   # replaces only the body; url/headers/token come from alerting.custom
          body: |
            {
              "type": "link",
              "title": "[ENDPOINT_NAME] - [ALERT_TRIGGERED_OR_RESOLVED]",
              "body": "📁 Group: [ENDPOINT_GROUP]\n🔔 Alert: [ALERT_DESCRIPTION]\n⚠️ Reason: [RESULT_ERRORS]",
              "url": "https://uptime.n8io.com/endpoints/media-management_plex-app-view"
            }
  - name: Plex remote access
    group: Media Management
    token: "${PLEX_CLIENT_CHECK_TOKEN}"
    heartbeat:
      interval: 10m
    alerts:
      - type: custom
        failure-threshold: 3
        success-threshold: 2
        send-on-resolved: true
        description: "Plex apps outside the house can't reach N8Flix"
        provider-override:
          body: |
            {
              "type": "link",
              "title": "[ENDPOINT_NAME] - [ALERT_TRIGGERED_OR_RESOLVED]",
              "body": "📁 Group: [ENDPOINT_GROUP]\n🔔 Alert: [ALERT_DESCRIPTION]\n⚠️ Reason: [RESULT_ERRORS]",
              "url": "https://uptime.n8io.com/endpoints/media-management_plex-remote-access"
            }
```

The shared `alerting.custom` body (all other Gatus alerts) also got a `⚠️ Reason: [RESULT_ERRORS]` line on 2026-11-08.

Deployed 2026-11-08. Gatus backups on the VPS: `/root/backups/plex-client-check-20261108T130755Z/` (`config.yaml` + `.env` original, `config.yaml.before-links`, `config.yaml.before-reason`). Tested by setting `SERVER_NAME=N8FlixTEST`: DOWN push after 2 runs with reason "record name is 'N8Flix', expected 'N8FlixTEST' (token hijack?)", then UP after restoring.

## Run it by hand

```
sudo systemctl start plex-client-check; journalctl -u plex-client-check -n 5
sudo PLEX_CLIENT_CHECK_ENV=/etc/plex-client-check.env python3 /opt/plex-client-check/plex-client-check.py --dry-run   # no push
```

## When it fires

- **"plex.tv says version 'v…'" / "record name is …"**: something is using the server's token. Find it (Tautulli, scripts, n8n) and give it its own token via plex.tv/link, then `systemctl restart plexmediaserver` so Plex republishes its record.
- **"version … below app minimum"**: update Plex (`apt` unattended upgrades should do it) and raise `MIN_VERSION` if apps changed it.
- **"second owned server named N8Flix"**: an old box came back or something registered as a server. Remove it at https://app.plex.tv/desktop/#!/settings/devices/all.
- **remote access**: port 32400 / firewall / Plex down / plex.direct cert. Compare with the plain `Plex` uptime check.
