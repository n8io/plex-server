#!/usr/bin/env python3
"""Weekly deletion-candidate rating (DCR) for Plex. NEVER deletes anything.

Scores every movie/show 0-100 (higher = better to delete), then keeps two Plex Janitor
(Maintainerr) "Leaving soon" collections in sync with the top titles, so users see
what may go and can save something by watching it or adding it to their watchlist.
It never deletes anything itself. With AUTO_APPROVE=1 (Nate, 2026-11-16) every title that has
been in Leaving soon for GRACE_DAYS is added to the Plex collection "Approved for Deletion";
the n8n "Plex | Delete Approved Media" workflow then deletes up to 25 of those per daily run.

DCR (100) = audience 35 + time since last play 20 + unpopularity 25 + depth 10 + size 10
  audience: distinct Plex accounts that ever played it: 0=35 1=28 2=18 3=10 4-5=5 6+=0
  stale:    0 if anyone played it < 90 days ago, rising to 20 at 3 years (never played:
            counted from the day it was added)
  unpop:    IMDb vote count (15) and rating (10), as a percentile within the library
            (movies vs movies, shows vs shows); Plex's audience rating when IMDb has none
  depth:    movies by total plays 0=10 1=7 2=4 3-4=2 5+=0; shows by the share of
            episodes ever played, 0%=10 falling to 0 at 50%
  size:     percentile of size among all titles
Not scored: excluded sections (Workouts) and titles added < 90 days ago.
Never listed: titles on anyone's watchlist, and shows still airing (Sonarr status not "ended")
that anyone played in the last AIRING_WATCHED_DAYS (Nate, 2026-11-18: 2 years). A show Sonarr
doesn't know, or any show when Sonarr can't be reached, counts as still airing.

Config: /etc/plex-dcr.env (root 600). See README.md.
"""
import bisect, csv, datetime as dt, gzip, io, json, os, shutil, sqlite3, subprocess, sys, time
import urllib.request, urllib.error, base64, fcntl

def env(k, d=None):
    return os.environ.get(k, d)

def load_env(path):
    if not os.path.exists(path):
        return
    for line in open(path):
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, v = line.split('=', 1)
        v = v.strip()
        if v[:1] in '"\'' and len(v) > 1 and v[-1] == v[0]:
            v = v[1:-1]                      # quoted value: keep as is (may contain #)
        else:
            v = v.split(' #', 1)[0].split('\t#', 1)[0].strip()  # drop inline comments
        os.environ.setdefault(k.strip(), v)

load_env(env('ENV_FILE', '/etc/plex-dcr.env'))
PMS = env('PMS', '/var/lib/plexmediaserver/Library/Application Support/Plex Media Server')
DB = os.path.join(PMS, 'Plug-in Support/Databases/com.plexapp.plugins.library.db')
SQLITE = env('PLEX_SQLITE', '/usr/lib/plexmediaserver/Plex SQLite')
STATE = env('STATE_DIR', '/var/lib/plex-dcr')
LOG = env('LOG', '/var/log/plex-dcr.log')
DRY = env('DRY_RUN', '1').strip() != '0'   # anything but an explicit 0 stays a dry run
TARGET = float(env('TARGET_TB', '10')) * 1e12
MIN_DCR = int(env('MIN_DCR', '60'))
EXCLUDE_SECTIONS = {s.strip() for s in env('EXCLUDE_SECTIONS', 'Workouts').split(',') if s.strip()}
EXCLUDE_WATCHLISTED = env('EXCLUDE_WATCHLISTED', '1') == '1'
GRACE = int(env('GRACE_DAYS', '30'))
AIRING_DAYS = int(env('AIRING_WATCHED_DAYS', '730'))  # 0 = off
AUTO_APPROVE = env('AUTO_APPROVE', '0').strip() == '1'
APPROVED = 'Approved for Deletion'
PLEX = env('PLEX_URL', 'http://127.0.0.1:32400')
NEW_DAYS = 90
# Plex Janitor collections are per library: "Plex library name=collection id", comma-separated
COLLS = {k.strip(): int(v) for k, v in (p.rsplit('=', 1) for p in env('LEAVING_SOON_COLLECTIONS', '').split(',') if '=' in p)}
NOW = dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)

def log(msg):
    line = f"{NOW:%Y-%m-%dT%H:%M:%SZ} {msg}"
    print(line)
    try:
        open(LOG, 'a').write(line + '\n')
    except OSError:
        pass

def http(url, method='GET', body=None, headers=None, timeout=60):
    h = dict(headers or {})
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        h['Content-Type'] = 'application/json'
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read()
        return json.loads(raw) if raw.strip() else None

def push(title, body, url=None):
    tok = env('PUSHBULLET_TOKEN')
    log(f"PUSH: {title}: {body.splitlines()[0] if body else ''}")
    if not tok:
        return
    msg = {'type': 'link' if url else 'note', 'title': title, 'body': body}
    if url:
        msg['url'] = url
    try:
        http('https://api.pushbullet.com/v2/pushes', 'POST', msg, {'Access-Token': tok}, 15)
    except Exception as e:
        log(f"pushbullet failed: {e}")

# ---------- data ----------
def drop_copy(copy):
    for f in (copy, copy + '-wal', copy + '-shm'):
        if os.path.exists(f):
            os.remove(f)

def snapshot_db():
    os.makedirs(STATE, exist_ok=True)
    copy = os.path.join(STATE, 'library-copy.db')
    drop_copy(copy)
    subprocess.run([SQLITE, DB, f".backup '{copy}'"], check=True, timeout=1800)
    return copy

def ts(v):
    if v is None or v == '':
        return None
    if isinstance(v, (int, float)):
        return dt.datetime.fromtimestamp(v, dt.timezone.utc).replace(tzinfo=None)
    return dt.datetime.strptime(str(v)[:19], '%Y-%m-%d %H:%M:%S')

def read_plex(path):
    con = sqlite3.connect(f'file:{path}?mode=ro', uri=True)
    q = lambda s: con.execute(s).fetchall()
    sections = {i: n for i, n in q("SELECT id, name FROM library_sections")}
    accounts = {i: n for i, n in q("SELECT id, name FROM accounts")}
    items, by_id = [], {}
    for i, sec, mt, title, year, guid, added, arating in q(
            "SELECT id, library_section_id, metadata_type, title, year, guid, added_at, audience_rating "
            "FROM metadata_items WHERE metadata_type IN (1,2) AND deleted_at IS NULL"):
        if sec not in sections:  # orphaned items (e.g. section -2) aren't in any library
            continue
        it = dict(id=i, section=sections[sec], type='movie' if mt == 1 else 'show', title=title,
                  year=year, guid=guid, added=ts(added), arating=arating, bytes=0, eps=0, ext={})
        items.append(it); by_id[i] = it
    for mid, tag in q("SELECT tg.metadata_item_id, t.tag FROM taggings tg JOIN tags t ON t.id = tg.tag_id WHERE t.tag_type = 314"):
        if mid in by_id and '://' in (tag or ''):
            k, v = tag.split('://', 1); by_id[mid]['ext'][k] = v
    parent = {i: p for i, p in q("SELECT id, parent_id FROM metadata_items WHERE metadata_type IN (3,4) AND deleted_at IS NULL")}
    eptype = {i for (i,) in q("SELECT id FROM metadata_items WHERE metadata_type = 4 AND deleted_at IS NULL")}
    def show_of(ep):
        return parent.get(parent.get(ep))
    for e in eptype:
        s = show_of(e)
        if s in by_id: by_id[s]['eps'] += 1
    for mid, size in q("SELECT mi.metadata_item_id, SUM(mp.size) FROM media_items mi JOIN media_parts mp ON mp.media_item_id = mi.id "
                       "WHERE mi.deleted_at IS NULL GROUP BY mi.metadata_item_id"):
        tgt = mid if mid in by_id else show_of(mid)
        if tgt in by_id: by_id[tgt]['bytes'] += size or 0
    guid_item = {it['guid']: it for it in items}
    for it in items:
        it.update(users=set(), plays=0, last=None, weps=set())
    for acct, guid, mt, gguid, viewed in q("SELECT account_id, guid, metadata_type, grandparent_guid, viewed_at FROM metadata_item_views"):
        it = guid_item.get(guid if mt == 1 else gguid)
        if not it: continue
        it['users'].add(accounts.get(acct, str(acct))); it['plays'] += 1
        v = ts(viewed)
        if v and (it['last'] is None or v > it['last']): it['last'] = v
        if mt == 4: it['weps'].add(guid)
    con.close()
    return items

def imdb_ratings():
    path = os.path.join(STATE, 'title.ratings.tsv.gz')
    if not os.path.exists(path) or time.time() - os.path.getmtime(path) > 6 * 86400:
        urllib.request.urlretrieve('https://datasets.imdbws.com/title.ratings.tsv.gz', path + '.tmp')
        os.replace(path + '.tmp', path)
    out = {}
    with gzip.open(path, 'rt') as f:
        next(f)
        for line in f:
            t, r, v = line.rstrip('\n').split('\t')
            out[t] = (float(r), int(v))
    return out

def watchlists():
    """{(type, tmdbId): set(user)} from Seerr (each user's Plex watchlist). Empty on failure."""
    url, key = env('SEERR_URL'), env('SEERR_API_KEY')
    out = {}
    if not (url and key):
        log('watchlists skipped: SEERR_URL/SEERR_API_KEY not set'); return out, 'not configured'
    H = {'X-Api-Key': key}
    try:
        users = http(f"{url}/api/v1/user?take=1000", headers=H)['results']
    except Exception as e:
        log(f'watchlists failed: {e}'); return out, f'failed ({e})'
    for u in users:
        name = (u.get('displayName') or u.get('plexUsername') or str(u['id'])).strip()
        page = 1
        while page < 50:
            try:
                r = http(f"{url}/api/v1/user/{u['id']}/watchlist?page={page}", headers=H)
            except Exception as e:
                log(f'watchlist {name}: {e}'); break
            for w in r.get('results', []):
                out.setdefault(('movie' if w.get('mediaType') == 'movie' else 'show', str(w.get('tmdbId'))), set()).add(name)
            if page >= r.get('totalPages', 1): break
            page += 1
    return out, 'ok'

# ---------- scoring ----------
def pctl(vals):
    s = sorted(vals)
    return lambda x: bisect.bisect_left(s, x) / max(1, len(s) - 1)

def score(items, imdb, wl):
    AUD = {0: 35, 1: 28, 2: 18, 3: 10, 4: 5, 5: 5}
    pool = [i for i in items if i['section'] not in EXCLUDE_SECTIONS and i['bytes'] > 0]
    for it in pool:
        ir = imdb.get(it['ext'].get('imdb'))
        it['imdb_rating'], it['imdb_votes'] = ir if ir else (None, None)
        it['watchlist'] = sorted(wl.get((it['type'], it['ext'].get('tmdb', '')), ()))
    P = {}
    for t in ('movie', 'show'):
        L = [i for i in pool if i['type'] == t]
        P[t] = (pctl([i['imdb_votes'] for i in L if i['imdb_votes']]),
                pctl([i['imdb_rating'] if i['imdb_rating'] is not None else (i['arating'] or 0) for i in L]))
    sp = pctl([i['bytes'] for i in pool])
    for it in pool:
        it['dcr'] = None
        if it['added'] and (NOW - it['added']).days < NEW_DAYS:
            continue
        n = len(it['users'])
        aud = AUD.get(n, 0)
        ref = it['last'] or it['added'] or NOW
        days = (NOW - ref).days
        stale = 0 if days < 90 else min(20, 20 * (days - 90) / (3 * 365 - 90))
        vp, rp = P[it['type']]
        rating = it['imdb_rating'] if it['imdb_rating'] is not None else it['arating']
        unpop = (15 * (1 - vp(it['imdb_votes'])) if it['imdb_votes'] else 10) + (10 * (1 - rp(rating)) if rating else 5)
        if it['type'] == 'movie':
            depth = {0: 10, 1: 7, 2: 4, 3: 2, 4: 2}.get(it['plays'], 0)
        else:
            frac = min(1, len(it['weps']) / max(1, it['eps']))
            depth = 10 * (1 - min(1, frac / 0.5))
        size = 10 * sp(it['bytes'])
        it['parts'] = [round(aud), round(stale), round(unpop), round(depth), round(size)]
        it['dcr'] = round(aud + stale + unpop + depth + size)
    return [i for i in pool if i['dcr'] is not None]

def sonarr_status():
    """({tvdbId: status}, note) from Sonarr. Empty map on failure: then every watched show counts as airing."""
    url, key = env('SONARR_URL', '').rstrip('/'), env('SONARR_API_KEY', '')
    if not url or not key:
        log('sonarr status skipped: SONARR_URL/SONARR_API_KEY not set'); return {}, 'Sonarr not configured, all watched shows protected'
    try:
        rows = http(f'{url}/api/v3/series', headers={'X-Api-Key': key, 'Accept': 'application/json'}, timeout=120)
        return {str(r.get('tvdbId')): (r.get('status') or '').lower() for r in rows}, f'{len(rows)} series'
    except Exception as e:
        log(f'sonarr status failed: {e}'); return {}, f'Sonarr failed ({e}), all watched shows protected'

def airing_watched(it, status):
    """Still-airing show that someone played within AIRING_DAYS: never offered for deletion."""
    if not AIRING_DAYS or it['type'] != 'show' or not it['last']: return False
    if (NOW - it['last']).days >= AIRING_DAYS: return False
    return status.get(str(it['ext'].get('tvdb', ''))) != 'ended'

def select(scored, status=None):
    status = status or {}
    picked, total = [], 0
    for it in sorted(scored, key=lambda i: (-i['dcr'], -i['bytes'])):
        if (TARGET > 0 and total >= TARGET) or it['dcr'] < MIN_DCR: break
        if EXCLUDE_WATCHLISTED and it['watchlist']: continue
        if airing_watched(it, status): it['airing'] = True; continue
        if COLLS and it['section'] not in COLLS: continue  # no Leaving soon collection for that library
        picked.append(it); total += it['bytes']
    return picked, total

# ---------- Plex Janitor (Maintainerr) ----------
def janitor(path, method='GET', body=None):
    url, auth = env('MAINTAINERR_URL'), env('MAINTAINERR_AUTH', '')
    H = {'Authorization': 'Basic ' + base64.b64encode(auth.encode()).decode()} if auth else {}
    return http(url.rstrip('/') + path, method, body, H)

def sync_collection(cid, want):
    """Make collection cid's manual members == want (set of Plex ratingKeys as str)."""
    cur = {str(m['mediaServerId']) for m in (janitor(f'/api/collections/media?collectionId={cid}') or [])}
    add, rem = sorted(want - cur), sorted(cur - want)
    if DRY:
        return add, rem
    for i in range(0, len(add), 100):
        janitor('/api/collections/add', 'POST', {'collectionId': cid, 'media': [{'mediaServerId': k} for k in add[i:i+100]], 'manual': True})
    if rem:
        janitor('/api/collections/remove', 'POST', {'collectionId': cid, 'media': [{'mediaServerId': k} for k in rem]})
    return add, rem

# ---------- Plex "Approved for Deletion" ----------
def plex_token():
    import re
    try:
        m = re.search(r'PlexOnlineToken="([^"]+)"', open(os.path.join(PMS, 'Preferences.xml')).read())
    except OSError:
        m = None
    if not m:
        raise RuntimeError('no Plex token in Preferences.xml')
    return m.group(1)

def approve(ready):
    """Add ready titles to each library's "Approved for Deletion" collection. Only adds, never removes:
    a title that leaves Leaving soon is safe anyway (the delete needs both collections),
    and Nate can still add titles by hand."""
    if not ready:
        return 0
    import urllib.parse
    tok = plex_token()
    H = {'X-Plex-Token': tok, 'Accept': 'application/json'}
    def call(path, method='GET'):
        return http(PLEX + path, method, None, H)
    mid = call('/identity')['MediaContainer']['machineIdentifier']
    secs = {d['title']: d for d in call('/library/sections')['MediaContainer'].get('Directory', [])}
    added = 0
    for name in sorted({i['section'] for i in ready}):
        d = secs.get(name)
        if not d:
            continue
        colls = call(f"/library/sections/{d['key']}/collections")['MediaContainer'].get('Metadata', [])
        appr = next((c for c in colls if c['title'].lower().startswith(APPROVED.lower())), None)
        have = set()
        if appr:
            have = {str(m['ratingKey']) for m in call(f"/library/collections/{appr['ratingKey']}/children")['MediaContainer'].get('Metadata', [])}
        keys = [str(i['id']) for i in ready if i['section'] == name and str(i['id']) not in have]
        for n in range(0, len(keys), 50):
            chunk = keys[n:n + 50]
            uri = urllib.parse.quote(f"server://{mid}/com.plexapp.plugins.library/library/metadata/{','.join(chunk)}", safe='')
            if appr:
                call(f"/library/collections/{appr['ratingKey']}/items?uri={uri}", 'PUT')
            else:
                t = 2 if d['type'] == 'show' else 1
                r = call(f"/library/collections?type={t}&title={urllib.parse.quote(APPROVED)}&smart=0&sectionId={d['key']}&uri={uri}", 'POST')
                appr = r['MediaContainer']['Metadata'][0]
            added += len(chunk)
    return added

# ---------- main ----------
def gb(b): return f"{b/1e12:.2f} TB" if b >= 1e12 else f"{b/1e9:.0f} GB"

def main():
    os.makedirs(STATE, exist_ok=True)
    lock = open(os.path.join(STATE, '.lock'), 'w')
    try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError: return
    log(f"start (dry_run={DRY}, target={TARGET/1e12:g} TB{' (no cap)' if TARGET <= 0 else ''}, min_dcr={MIN_DCR})")
    copy = snapshot_db()
    try:
        items = read_plex(copy)
    finally:
        drop_copy(copy)
    imdb = imdb_ratings()
    wl, wl_status = watchlists()
    scored = score(items, imdb, wl)
    status, st_note = sonarr_status()
    picked, total = select(scored, status)
    airing = [i for i in scored if i.get('airing')]
    # first-seen state for the grace period
    sf = os.path.join(STATE, 'state.json')
    seen = json.load(open(sf)) if os.path.exists(sf) else {}
    keys = {str(i['id']) for i in picked}
    today = NOW.strftime('%Y-%m-%d')
    seen = {k: v for k, v in seen.items() if k in keys}
    for k in keys: seen.setdefault(k, today)
    ready = [i for i in picked if (NOW - dt.datetime.strptime(seen[str(i['id'])], '%Y-%m-%d')).days >= GRACE]
    # Plex Janitor
    jstat = 'not configured'
    if env('MAINTAINERR_URL') and COLLS:
        try:
            a = r = 0
            for sec, cid in COLLS.items():
                ad, rm = sync_collection(cid, {str(i['id']) for i in picked if i['section'] == sec})
                a += len(ad); r += len(rm)
            jstat = f"{'would add' if DRY else 'added'} {a}, {'would remove' if DRY else 'removed'} {r}"
        except Exception as e:
            jstat = f'FAILED ({e})'
    if not DRY:
        json.dump(seen, open(sf, 'w'))
    # report data (for the HTML report / approvals)
    rep = [dict(key=i['id'], t=i['title'], y=i['year'], k=i['type'], s=i['section'], b=i['bytes'], e=i['eps'], we=len(i['weps']),
                ir=i['imdb_rating'], iv=i['imdb_votes'], im=i['ext'].get('imdb'), tmdb=i['ext'].get('tmdb'), tvdb=i['ext'].get('tvdb'),
                n=len(i['users']), u=sorted(i['users'])[:3], p=i['plays'], l=i['last'].strftime('%Y-%m-%d') if i['last'] else '',
                a=i['added'].strftime('%Y-%m-%d') if i['added'] else '', w=i['watchlist'], d=i['dcr'], pa=i['parts'],
                leaving=str(i['id']) in keys, since=seen.get(str(i['id'])), air=bool(i.get('airing')))
           for i in sorted(scored, key=lambda i: (-i['dcr'], -i['bytes']))]
    json.dump({'generated': NOW.isoformat() + 'Z', 'target': TARGET, 'rows': rep}, open(os.path.join(STATE, 'report.json'), 'w'))
    astat = ''
    if AUTO_APPROVE and not DRY:
        try:
            astat = f"Auto-approved for deletion: {approve(ready)} new; the daily delete takes up to 25 per run.\n"
        except Exception as e:
            jstat = f'FAILED (auto-approve: {e})'
    rb = sum(i['bytes'] for i in ready)
    body = (f"Leaving soon: {len(picked)} titles, {gb(total)} (DCR >= {picked[-1]['dcr'] if picked else '-'}).\n"
            f"Past the {GRACE}-day grace period{' (deleted automatically)' if AUTO_APPROVE else ' and ready for your approval'}: {len(ready)} titles, {gb(rb)}.\n"
            + astat +
            f"Plex Janitor: {jstat}. Watchlists: {wl_status}.\n"
            f"Kept as still airing and watched in the last {AIRING_DAYS} days: {len(airing)} shows, {gb(sum(i['bytes'] for i in airing))} ({st_note}).\n"
            + ''.join(f"- {i['title']} ({i['year']}) {gb(i['bytes'])} DCR {i['dcr']}\n" for i in ready[:15])
            + ("Nothing is deleted until you approve it in the Plex project." if ready and not AUTO_APPROVE else ""))
    log(body.replace('\n', ' | '))
    if not DRY or env('PUSH_IN_DRY_RUN') == '1':
        push(('[dry run] ' if DRY else '') + 'Plex cleanup (DCR) weekly', body, env('REPORT_URL') or 'https://app.plex.tv/desktop')
    if jstat.startswith('FAILED'):
        if DRY and env('PUSH_IN_DRY_RUN') != '1':
            log(f'dry run: not pushing failure ({jstat})'); sys.exit(1)
        push('Plex cleanup (DCR) failed', f'Plex Janitor sync failed: {jstat}. Check /var/log/plex-dcr.log on the Plex box.', 'https://plex-janitor.n8io.com')
        sys.exit(1)

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        log(f'ERROR: {e}')
        if os.environ.get('DRY_RUN', '1').strip() == '0' or env('PUSH_IN_DRY_RUN') == '1':
            push('Plex cleanup (DCR) failed', f'The weekly DCR job crashed: {e}. Check /var/log/plex-dcr.log on the Plex box.', 'https://app.plex.tv/desktop')
        raise
