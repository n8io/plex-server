#!/usr/bin/env python3
"""Check Plex the way a client app sees it, and report to Gatus.

Why: on 2026-11-08 every Plex app blocked N8Flix with "Server is Outdated
(needs 1.41.2+)". Plex itself was up (1.43.5), so the /identity uptime check
stayed green. Tautulli had been signed in with the server's own token, so
plex.tv stored Tautulli's name and version (v2.18.2) on the server's record.
Apps trust that record, not the server.

Two checks, each pushed to its own Gatus external endpoint (Gatus does the
alerting, thresholds and Pushbullet):

  record  plex.tv's record for the server is sane: present, owned, product
          "Plex Media Server", expected name, version 1.x >= MIN_VERSION and
          equal to what the server itself reports; no second owned server
          using the same name.
  remote  a remote (non-local, non-relay) connection that plex.tv hands to
          apps works: /identity answers with the right machineIdentifier, and
          /library/sections lists libraries with the token apps get.

Runs off-box (Coolify VPS), every few minutes, from a systemd timer.
Uses its own plex.tv device token (never the server's PlexOnlineToken; that
was the bug). Create one with:  plex-client-check.py --link

Config: /etc/plex-client-check.env (KEY=value lines), see README in docs.
Exit status: 0 all good, 1 a check failed, 2 config/usage error.
"""
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ENV_FILE = os.environ.get("PLEX_CLIENT_CHECK_ENV", "/etc/plex-client-check.env")
PRODUCT = "plex-client-check"
TIMEOUT = 15


def load_env(path):
    cfg = {}
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    cfg[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    cfg.update({k: v for k, v in os.environ.items() if k.startswith(("PLEX_", "GATUS_", "SERVER_", "MIN_"))})
    return cfg


def http(method, url, headers=None, data=None, timeout=TIMEOUT):
    req = urllib.request.Request(url, method=method, headers=headers or {}, data=data)
    with urllib.request.urlopen(req, timeout=timeout, context=ssl.create_default_context()) as r:
        return r.status, r.read()


def plex_headers(cfg, token=None):
    h = {
        "Accept": "application/json",
        "X-Plex-Product": PRODUCT,
        "X-Plex-Client-Identifier": cfg.get("PLEX_CLIENT_ID", "n8io-plex-client-check"),
        "X-Plex-Device-Name": "Plex client check",
    }
    if token:
        h["X-Plex-Token"] = token
    return h


def vtuple(v):
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)", v or "")
    return tuple(int(x) for x in m.groups()) if m else None


def check_record(cfg, resources, server_identity):
    """Returns (problems, server_resource)."""
    sid = cfg["SERVER_ID"]
    name = cfg.get("SERVER_NAME", "N8Flix")
    minv = vtuple(cfg.get("MIN_VERSION", "1.41.2"))
    p = []
    mine = [r for r in resources if r.get("clientIdentifier") == sid]
    if not mine:
        return [f"plex.tv has no device {sid[:8]}… on the account"], None
    r = mine[0]
    pv = r.get("productVersion", "")
    if "server" not in (r.get("provides") or ""):
        p.append(f"record no longer provides 'server' (provides={r.get('provides')})")
    if r.get("product") != "Plex Media Server":
        p.append(f"record product is '{r.get('product')}', not Plex Media Server (token hijack?)")
    if r.get("name") != name:
        p.append(f"record name is '{r.get('name')}', expected '{name}' (token hijack?)")
    if not r.get("owned"):
        p.append("record is not owned by this account")
    if not r.get("presence"):
        p.append(f"plex.tv shows the server offline (lastSeenAt {r.get('lastSeenAt')})")
    v = vtuple(pv)
    if not v or v[0] != 1:
        p.append(f"plex.tv says version {pv!r}; apps will call it outdated")
    elif minv and v < minv:
        p.append(f"plex.tv says version {pv}, below app minimum {cfg.get('MIN_VERSION')}")
    if server_identity and server_identity.get("version") and pv != server_identity["version"]:
        p.append(f"plex.tv version {pv!r} != server's own {server_identity['version']!r}")
    others = [x for x in resources if x is not r and "server" in (x.get("provides") or "")
              and x.get("owned") and x.get("name") == name]
    for x in others:
        p.append(f"second owned server named '{name}' on the account: {x.get('clientIdentifier', '')[:8]}… "
                 f"({x.get('product')} {x.get('productVersion')}, presence={x.get('presence')})")
    return p, r


def check_remote(cfg, r):
    """Try the connections an app outside the LAN would use. Returns (problems, identity)."""
    if not r:
        return ["no server record to get connections from"], None
    token = r.get("accessToken")
    conns = [c for c in r.get("connections", []) if not c.get("local") and not c.get("relay")]
    if not conns:
        return ["plex.tv advertises no remote (non-local, non-relay) connection"], None
    conns.sort(key=lambda c: c.get("IPv6", False))  # IPv4 first, like most networks
    errs = []
    for c in conns:
        base = c["uri"].rstrip("/")
        try:
            _, body = http("GET", base + "/identity", plex_headers(cfg, token))
            ident = json.loads(body)["MediaContainer"]
            if ident.get("machineIdentifier") != cfg["SERVER_ID"]:
                errs.append(f"{base}: answers as {ident.get('machineIdentifier', '?')[:8]}…, not our server")
                continue
            _, body = http("GET", base + "/library/sections", plex_headers(cfg, token))
            secs = json.loads(body)["MediaContainer"].get("Directory", [])
            if not secs:
                errs.append(f"{base}: /library/sections is empty")
                continue
            return [], ident
        except urllib.error.HTTPError as e:
            errs.append(f"{base}: HTTP {e.code}")
        except Exception as e:  # noqa: BLE001 - report anything as a failed connection
            errs.append(f"{base}: {type(e).__name__}: {e}")
    return ["no remote connection works: " + "; ".join(errs)], None


def push(cfg, key, ok, err, dry):
    url = cfg.get("GATUS_URL", "").rstrip("/")
    if dry or not url:
        return
    q = {"success": "true" if ok else "false"}
    if err:
        q["error"] = err[:900]
    try:
        http("POST", f"{url}/api/v1/endpoints/{urllib.parse.quote(key)}/external?{urllib.parse.urlencode(q)}",
             {"Authorization": f"Bearer {cfg['GATUS_TOKEN']}"}, data=b"")
    except Exception as e:  # noqa: BLE001
        print(f"gatus push for {key} failed: {e}", file=sys.stderr)


def link(cfg):
    """Give this checker its own plex.tv token via plex.tv/link (no password on the box).

    Prints a 4-character code; the account owner enters it at https://plex.tv/link.
    The token is then written to ENV_FILE (mode 600) and never printed.
    """
    _, body = http("POST", "https://plex.tv/api/v2/pins", plex_headers(cfg), data=b"")
    pin = json.loads(body)
    print(f"Open https://plex.tv/link as the server owner and enter: {pin['code']}", flush=True)
    for _ in range(180):
        time.sleep(5)
        _, body = http("GET", f"https://plex.tv/api/v2/pins/{pin['id']}", plex_headers(cfg))
        tok = json.loads(body).get("authToken")
        if tok:
            lines = []
            if os.path.exists(ENV_FILE):
                with open(ENV_FILE) as f:
                    lines = [x for x in f if not x.startswith(("PLEX_TOKEN=", "PLEX_CLIENT_ID="))]
            lines += [f"PLEX_TOKEN={tok}\n", f"PLEX_CLIENT_ID={plex_headers(cfg)['X-Plex-Client-Identifier']}\n"]
            fd = os.open(ENV_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as f:
                f.writelines(lines)
            os.chmod(ENV_FILE, 0o600)
            print(f"linked; token saved to {ENV_FILE}")
            return 0
    print("timed out waiting for the code to be linked", file=sys.stderr)
    return 2


def main():
    args = sys.argv[1:]
    cfg = load_env(ENV_FILE)
    if "--link" in args:
        return link(cfg)
    dry = "--dry-run" in args
    for k in ("PLEX_TOKEN", "SERVER_ID") + (() if dry else ("GATUS_URL", "GATUS_TOKEN")):
        if not cfg.get(k):
            print(f"missing {k} in {ENV_FILE}", file=sys.stderr)
            return 2
    try:
        _, body = http("GET", "https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1",
                       plex_headers(cfg, cfg["PLEX_TOKEN"]))
        resources = json.loads(body)
    except urllib.error.HTTPError as e:
        if e.code == 401:
            msg = "plex.tv rejected the checker's token (401); relink with --link"
        else:
            msg = f"plex.tv resources API: HTTP {e.code}"
        resources = None
    except Exception as e:  # noqa: BLE001
        resources, msg = None, f"plex.tv resources API: {type(e).__name__}: {e}"

    if resources is None:
        # Can't judge the server when plex.tv itself is unreachable; report on the record check only.
        results = {"record": [msg]}
    else:
        server = next((r for r in resources if r.get("clientIdentifier") == cfg["SERVER_ID"]), None)
        remote_p, ident = check_remote(cfg, server)
        record_p, _ = check_record(cfg, resources, ident)
        results = {"record": record_p, "remote": remote_p}

    keys = {"record": cfg.get("GATUS_KEY_RECORD", "media-management_plex-app-view"),
            "remote": cfg.get("GATUS_KEY_REMOTE", "media-management_plex-remote-access")}
    failed = False
    for name, problems in results.items():
        ok = not problems
        failed |= not ok
        print(f"{name}: {'OK' if ok else 'FAIL: ' + ' | '.join(problems)}")
        push(cfg, keys[name], ok, " | ".join(problems), dry)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
