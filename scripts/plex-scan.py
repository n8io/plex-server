#!/usr/bin/env python3
"""Scan one show/movie folder in Plex. Invoked by plex-scan.sh (which supplies
PLEX_URL, PLEX_TOKEN and DEC_DIR_LOCAL). Python 3.5 compatible."""
import argparse
import difflib
import os
import re
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

URL = os.environ.get("PLEX_URL", "http://localhost:32400").rstrip("/")
TOKEN = os.environ.get("PLEX_TOKEN", "")
DEC_DIR = os.environ.get("DEC_DIR_LOCAL", "/mnt/x/decrypted").rstrip("/")
KINDS = {"tv": "show", "movie": "movie"}


def norm(s):
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()


def api(path, params=None):
    params = dict(params or {})
    params["X-Plex-Token"] = TOKEN
    url = "%s%s?%s" % (URL, path, urllib.parse.urlencode(params))
    req = urllib.request.Request(url, headers={"Accept": "application/xml"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.status, r.read()


def public_url(path, params):
    return "%s%s?%s" % (URL, path, urllib.parse.urlencode(params))


def sections():
    _, body = api("/library/sections")
    out = []
    for d in ET.fromstring(body).findall("Directory"):
        out.append({
            "key": d.get("key"),
            "type": d.get("type"),
            "title": d.get("title"),
            "locations": [l.get("path").rstrip("/") for l in d.findall("Location")],
        })
    return out


def section_for(path, secs):
    best = None
    for s in secs:
        for loc in s["locations"]:
            if path == loc or path.startswith(loc + "/"):
                if best is None or len(loc) > len(best[1]):
                    best = (s, loc)
    return best[0] if best else None


def candidates(query, secs, kind):
    q = norm(query)
    res = []
    for s in secs:
        if kind and s["type"] != kind:
            continue
        for loc in s["locations"]:
            try:
                names = os.listdir(loc)
            except OSError as e:
                print("warning: cannot list %s: %s" % (loc, e), file=sys.stderr)
                continue
            for n in names:
                p = os.path.join(loc, n)
                if not os.path.isdir(p):
                    continue
                nn = norm(n)
                if q and q == nn:
                    score = 2.0                              # exact title
                elif q and q in nn:
                    score = 1.0 + len(q) / float(len(nn))   # substring hit; tighter name ranks higher
                else:
                    score = difflib.SequenceMatcher(None, q, nn).ratio()
                    if score < 0.6:
                        continue
                res.append((score, s, p))
    res.sort(key=lambda t: (-t[0], t[2]))
    # Only fall back to fuzzy near-misses when nothing contains the query.
    if any(c[0] >= 1.0 for c in res):
        res = [c for c in res if c[0] >= 1.0]
    return res


def choose(cands, auto_first):
    if len(cands) == 1 or auto_first or cands[0][0] >= 2.0:
        return cands[0]
    print("Multiple matches:")
    for i, (score, s, p) in enumerate(cands[:15], 1):
        print("  %2d) [%s] %s" % (i, s["title"], os.path.relpath(p, DEC_DIR)))
    if not sys.stdin.isatty():
        print("Not a terminal; re-run with -y to take the first match or give an exact path.", file=sys.stderr)
        sys.exit(2)
    try:
        ans = input("Pick one [1]: ").strip() or "1"
    except EOFError:
        sys.exit(2)
    if not ans.isdigit() or not 1 <= int(ans) <= min(len(cands), 15):
        sys.exit("invalid choice")
    return cands[int(ans) - 1]


def main():
    ap = argparse.ArgumentParser(prog="plex-scan", add_help=True)
    ap.add_argument("-t", "--tv", action="store_const", const="tv", dest="kind")
    ap.add_argument("-m", "--movie", action="store_const", const="movie", dest="kind")
    ap.add_argument("-f", "--force", action="store_true", help="also refresh metadata of existing items")
    ap.add_argument("-y", "--first", action="store_true", help="auto-pick the best match without prompting")
    ap.add_argument("-l", "--list", action="store_true", help="list matches and exit")
    ap.add_argument("-n", "--dry-run", action="store_true", help="show what would be scanned")
    ap.add_argument("query", nargs="+", help="show/movie name (fuzzy) or a folder path")
    a = ap.parse_args()
    query = " ".join(a.query).strip()
    if not TOKEN:
        sys.exit("plex-scan: PLEX_TOKEN not set")

    secs = sections()

    as_path = query if os.path.isabs(query) else os.path.join(DEC_DIR, query)
    as_path = os.path.normpath(as_path)
    if os.path.isdir(as_path):
        target = as_path
        sec = section_for(target, secs)
        if sec is None:
            sys.exit("plex-scan: %s is not inside any Plex library location" % target)
    else:
        kind = KINDS.get(a.kind)
        cands = candidates(query, secs, kind)
        if not cands:
            sys.exit("plex-scan: nothing matching '%s'%s" % (query, " in %s libraries" % a.kind if a.kind else ""))
        if a.list:
            for score, s, p in cands[:25]:
                print("[%s] %s" % (s["title"], os.path.relpath(p, DEC_DIR)))
            return
        _, sec, target = choose(cands, a.first)

    params = {"path": target}
    if a.force:
        params["force"] = "1"
    refresh = "/library/sections/%s/refresh" % sec["key"]
    print("Scanning [%s] %s%s" % (sec["title"], target, " (force)" if a.force else ""))
    if a.dry_run:
        print("dry-run: GET %s&X-Plex-Token=..." % public_url(refresh, params))
        return
    status, _ = api(refresh, params)
    if status == 200:
        print("OK - Plex is scanning that folder now (check the Activity panel or the server log).")
    else:
        sys.exit("plex-scan: Plex returned HTTP %s" % status)


if __name__ == "__main__":
    main()
