#!/usr/bin/env python3
"""Plex box: read-only media lookups for nzb2's media-api (n8io/nzb docs/media-api.md).

Forced SSH command for nzb2's media-check key, so that key can run nothing else:
  restrict,command="/plex-server/scripts/media-check.py",from="<nzb2 IP>" ssh-ed25519 AAAA... media-check@nzb2

Reads ONE JSON object on stdin and prints one JSON object:
  {"op": "ping"}
  {"op": "find", "kind": "movie"|"show", "ids": {"tmdb": 603, "tvdb": 81189, "imdb": "tt0133093"},
   "title": "The Matrix", "season": 1, "episode": 2}     -> is it in Plex? which files?
  {"op": "probe", "ratingKey": 82152, "seconds": 60}     -> ffprobe + decode test + Plex log lines

Never changes anything: no scans, no deletes, no settings.
"""
import glob
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

PLEX_URL = os.environ.get("PLEX_URL", "http://127.0.0.1:32400")
PMS = os.environ.get("PLEX_PMS_DIR", "/var/lib/plexmediaserver/Library/Application Support/Plex Media Server")
DEC_DIR = os.environ.get("DEC_DIR_LOCAL", "/mnt/x/decrypted").rstrip("/")
MAX_EPISODES = 60


def token():
    t = os.environ.get("PLEX_TOKEN")
    if t:
        return t
    with open(os.path.join(PMS, "Preferences.xml")) as f:
        m = re.search(r'PlexOnlineToken="([^"]+)"', f.read())
    return m.group(1) if m else ""


TOKEN = token()


def plex(path, **params):
    params["X-Plex-Token"] = TOKEN
    url = "%s%s?%s" % (PLEX_URL, path, urllib.parse.urlencode(params))
    with urllib.request.urlopen(urllib.request.Request(url, headers={"Accept": "application/xml"}), timeout=60) as r:
        return ET.fromstring(r.read())


def guids(el):
    return {g.get("id") for g in el.findall("Guid")}


def parts(el):
    out = []
    for m in el.findall("Media"):
        for p in m.findall("Part"):
            out.append({
                "file": p.get("file"), "sizeGB": round(int(p.get("size") or 0) / 1e9, 2),
                "container": m.get("container"), "videoCodec": m.get("videoCodec"),
                "resolution": m.get("videoResolution"), "videoProfile": m.get("videoProfile"),
                "bitrateKbps": m.get("bitrate"), "audio": m.get("audioCodec"),
                "durationMin": round(int(m.get("duration") or 0) / 60000),
                "exists": os.path.exists(p.get("file") or ""),
            })
    return out


def find(req):
    kind = req.get("kind")
    if kind not in ("movie", "show"):
        raise ValueError("kind must be movie or show")
    ids = req.get("ids") or {}
    want = set()
    for scheme in ("tmdb", "tvdb", "imdb"):
        v = ids.get(scheme)
        if v is not None and re.fullmatch(r"(tt)?\d{1,12}", str(v)):
            want.add("%s://%s" % (scheme, v))
    title = str(req.get("title") or "")[:200]
    season, episode = req.get("season"), req.get("episode")
    if not want:
        raise ValueError("need at least one id")

    secs = [d for d in plex("/library/sections").findall("Directory") if d.get("type") == kind]
    matches = []
    for d in secs:
        # Title filter narrows the scan; fall back to the whole section if the
        # title in Plex differs (punctuation, "The", year).
        for params in ({"title": title} if title else None, {}):
            if params is None:
                continue
            root = plex("/library/sections/%s/all" % d.get("key"), includeGuids=1, **params)
            hit = [el for el in root if guids(el) & want]
            if hit:
                matches += [(d, el) for el in hit]
                break

    items = []
    for d, el in matches:
        item = {"section": d.get("title"), "ratingKey": el.get("ratingKey"), "title": el.get("title"),
                "year": el.get("year"), "addedAt": el.get("addedAt")}
        if kind == "movie":
            item["parts"] = parts(plex("/library/metadata/%s" % el.get("ratingKey")).find("Video"))
            items.append(item)
            continue
        leaves = plex("/library/metadata/%s/allLeaves" % el.get("ratingKey"))
        eps = []
        for v in leaves.findall("Video"):
            s, e = int(v.get("parentIndex") or -1), int(v.get("index") or -1)
            if season is not None and s != int(season):
                continue
            if episode is not None and e != int(episode):
                continue
            eps.append({"ratingKey": v.get("ratingKey"), "season": s, "episode": e, "title": v.get("title"),
                        "addedAt": v.get("addedAt"), "parts": parts(v)})
        item["episodes"] = eps[:MAX_EPISODES]
        item["episodeCount"] = len(eps)
        if episode is not None:
            item["parts"] = eps[0]["parts"] if eps else []
        items.append(item)
    return {"ok": True, "items": items}


def run(cmd, timeout):
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        return -1, "", "timed out after %ss" % timeout
    except FileNotFoundError as e:
        return -2, "", str(e)


def ffprobe(path):
    rc, out, err = run(["ffprobe", "-v", "error", "-of", "json", "-show_format", "-show_streams", path], 180)
    if rc != 0:
        return {"error": (err or "ffprobe failed").strip()[:1000]}
    d = json.loads(out)
    streams = []
    for s in d.get("streams", []):
        side = [{k: v for k, v in sd.items() if k.startswith("dv_") or k == "side_data_type"}
                for sd in s.get("side_data_list", []) if "dv" in json.dumps(sd).lower()]
        streams.append({k: v for k, v in {
            "index": s.get("index"), "type": s.get("codec_type"), "codec": s.get("codec_name"),
            "profile": s.get("profile"), "width": s.get("width"), "height": s.get("height"),
            "pix_fmt": s.get("pix_fmt"), "transfer": s.get("color_transfer"),
            "channels": s.get("channels"), "layout": s.get("channel_layout"),
            "language": (s.get("tags") or {}).get("language"), "title": (s.get("tags") or {}).get("title"),
            "default": (s.get("disposition") or {}).get("default"), "dolbyVision": side or None,
        }.items() if v not in (None, "")})
    f = d.get("format", {})
    return {"format": f.get("format_name"), "durationMin": round(float(f.get("duration") or 0) / 60, 1),
            "bitrateKbps": round(int(f.get("bit_rate") or 0) / 1000), "streams": streams,
            "warnings": sorted(set(l.strip() for l in err.splitlines() if l.strip()))[:20]}


def decode_test(path, seconds):
    """Decode the first N seconds of video+audio; real decode errors show up here
    (e.g. 2026-11-10's broken Dolby Vision RPU: 'RPU validation failed')."""
    if seconds <= 0:
        return None
    rc, _, err = run(["ffmpeg", "-hide_banner", "-nostdin", "-v", "error", "-t", str(seconds), "-i", path,
                      "-map", "0:v:0", "-map", "0:a?", "-f", "null", "-"], seconds * 6 + 120)
    lines = [l.strip() for l in err.splitlines() if l.strip()]
    uniq = []
    for l in lines:
        k = re.sub(r"0x[0-9a-f]+|\d+", "#", l)
        if k not in [re.sub(r"0x[0-9a-f]+|\d+", "#", u) for u in uniq]:
            uniq.append(l)
    return {"seconds": seconds, "exit": rc, "errorLines": len(lines), "distinctErrors": uniq[:25]}


def plex_log_lines(rating_key, files):
    needles = ["/library/metadata/%s" % rating_key, "ratingKey=%s" % rating_key, "key=%s" % rating_key]
    needles += [os.path.basename(f) for f in files if f]
    logs = sorted(glob.glob(os.path.join(PMS, "Logs", "Plex Media Server*.log")) +
                  glob.glob(os.path.join(PMS, "Logs", "Plex Transcoder Statistics*.log")), key=os.path.getmtime)[-6:]
    hits = []
    for lf in logs:
        try:
            with open(lf, errors="replace") as fh:
                for line in fh:
                    if any(n in line for n in needles):
                        hits.append(line.rstrip()[:400])
        except OSError:
            pass
    tok = re.compile(r"(X-Plex-Token=)[^&\s]+")
    hits = [tok.sub(r"\1REDACTED", h) for h in hits]
    important = [h for h in hits if re.search(r"\b(ERROR|WARN)", h)]
    return {"matchingLines": len(hits), "errorsAndWarnings": important[-30:], "recent": hits[-15:]}


def probe(req):
    rk = str(req.get("ratingKey") or "")
    if not rk.isdigit():
        raise ValueError("ratingKey must be digits")
    seconds = max(0, min(int(req.get("seconds") or 60), 600))
    root = plex("/library/metadata/%s" % rk)
    el = root.find("Video")
    if el is None:
        raise ValueError("ratingKey %s isn't a movie or episode" % rk)
    out = {"ok": True, "ratingKey": rk, "title": el.get("title"), "show": el.get("grandparentTitle"),
           "season": el.get("parentIndex"), "episode": el.get("index"), "files": []}
    files = []
    for p in parts(el):
        f = p["file"]
        files.append(f)
        entry = dict(p)
        if not f or not os.path.realpath(f).startswith(DEC_DIR + "/"):
            entry["error"] = "file is outside %s; not probed" % DEC_DIR
        elif not p["exists"]:
            entry["error"] = "file missing on the mount"
        else:
            entry["ffprobe"] = ffprobe(f)
            entry["decode"] = decode_test(f, seconds)
        out["files"].append(entry)
    out["plexLog"] = plex_log_lines(rk, files)
    return out


def main():
    try:
        req = json.loads(sys.stdin.read(65536) or "{}")
        op = req.get("op")
        if op == "ping":
            plex("/identity")
            res = {"ok": True}
        elif op == "find":
            res = find(req)
        elif op == "probe":
            res = probe(req)
        else:
            raise ValueError("op must be ping, find or probe")
    except Exception as e:  # always answer in JSON so the caller can report it
        res = {"ok": False, "error": "%s: %s" % (type(e).__name__, e)}
    print(json.dumps(res))


if __name__ == "__main__":
    main()
