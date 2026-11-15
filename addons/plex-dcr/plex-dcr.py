#!/usr/bin/env python3
"""Weekly deletion-candidate rating (DCR) for Plex. NEVER deletes anything.

Scores every movie/show 0-100 (higher = better to delete), then keeps two Plex Janitor
(Maintainerr) "Leaving soon" collections in sync with the top titles, so users see
what may go and can save something by watching it or adding it to their watchlist.
Deletion stays manual: Nate approves titles; only approved titles are deleted
(rclone deletefile on the encrypted Drive path).

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
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

load_env(env('ENV_FILE', '/etc/plex-dcr.env'))
PMS = env('PMS', '/var/lib/plexmediaserver/Library/Application Support/Plex Media Server')
DB = os.path.join(PMS, 'Plug-in Support/Databases/com.plexapp.plugins.library.db')
SQLITE = env('PLEX_SQLITE', '/usr/lib/plexmediaserver/Plex SQLite')
STATE = env('STATE_DIR', '/var/lib/plex-dcr')
LOG = env('LOG', '/var/log/plex-dcr.log')
DRY = env('DRY_RUN', '1') == '1'
TARGET = float(env('TARGET_TB', '10')) * 1e12
MIN_DCR = int(env('MIN_DCR', '60'))
EXCLUDE_SECTIONS = {s.strip() for s in env('EXCLUDE_SECTIONS', 'Workouts').split(',') if s.strip()}
EXCLUDE_WATCHLISTED = env('EXCLUDE_WATCHLISTED', '1') == '1'
GRACE = int(env('GRACE_DAYS', '30'))
NEW_DAYS = 90
NOW = dt.datetime.utcnow()

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
def snapshot_db():
    os.makedirs(STATE, exist_ok=True)
    copy = os.path.join(STATE, 'library-copy.db')
    if os.path.exists(copy):
        os.remove(copy)
    subprocess.run([SQLITE, DB, f".backup '{copy}'"], check=True, timeout=1800)
    return copy

def ts(v):
    if v is None or v == '':
        return None
    if isinstance(v, (int, float)):
        return dt.datetime.utcfromtimestamp(v)
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
        it = dict(id=i, section=sections.get(sec, str(sec)), type='movie' if mt == 1 else 'show', title=title,
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
    pool = [i for i in items if i['section'] not in EXCLUDE_SECTIONS]
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

def select(scored):
    picked, total = [], 0
    for it in sorted(scored, key=lambda i: (-i['dcr'], -i['bytes'])):
        if total >= TARGET or it['dcr'] < MIN_DCR: break
        if EXCLUDE_WATCHLISTED and it['watchlist']: continue
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

# ---------- main ----------
def gb(b): return f"{b/1e12:.2f} TB" if b >= 1e12 else f"{b/1e9:.0f} GB"

def main():
    os.makedirs(STATE, exist_ok=True)
    lock = open(os.path.join(STATE, '.lock'), 'w')
    try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError: return
    log(f"start (dry_run={DRY}, target={TARGET/1e12:g} TB, min_dcr={MIN_DCR})")
    copy = snapshot_db()
    try:
        items = read_plex(copy)
    finally:
        os.remove(copy)
    imdb = imdb_ratings()
    wl, wl_status = watchlists()
    scored = score(items, imdb, wl)
    picked, total = select(scored)
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
    if env('MAINTAINERR_URL') and env('MOVIES_COLLECTION_ID') and env('SHOWS_COLLECTION_ID'):
        try:
            a1, r1 = sync_collection(int(env('MOVIES_COLLECTION_ID')), {str(i['id']) for i in picked if i['type'] == 'movie'})
            a2, r2 = sync_collection(int(env('SHOWS_COLLECTION_ID')), {str(i['id']) for i in picked if i['type'] == 'show'})
            jstat = f"{'would add' if DRY else 'added'} {len(a1)+len(a2)}, {'would remove' if DRY else 'removed'} {len(r1)+len(r2)}"
        except Exception as e:
            jstat = f'FAILED ({e})'
    if not DRY:
        json.dump(seen, open(sf, 'w'))
    # report data (for the HTML report / approvals)
    rep = [dict(key=i['id'], t=i['title'], y=i['year'], k=i['type'], s=i['section'], b=i['bytes'], e=i['eps'], we=len(i['weps']),
                ir=i['imdb_rating'], iv=i['imdb_votes'], im=i['ext'].get('imdb'), tmdb=i['ext'].get('tmdb'), tvdb=i['ext'].get('tvdb'),
                n=len(i['users']), u=sorted(i['users'])[:3], p=i['plays'], l=i['last'].strftime('%Y-%m-%d') if i['last'] else '',
                a=i['added'].strftime('%Y-%m-%d') if i['added'] else '', w=i['watchlist'], d=i['dcr'], pa=i['parts'],
                leaving=str(i['id']) in keys, since=seen.get(str(i['id'])))
           for i in sorted(scored, key=lambda i: (-i['dcr'], -i['bytes']))]
    json.dump({'generated': NOW.isoformat() + 'Z', 'target': TARGET, 'rows': rep}, open(os.path.join(STATE, 'report.json'), 'w'))
    rb = sum(i['bytes'] for i in ready)
    body = (f"Leaving soon: {len(picked)} titles, {gb(total)} (DCR >= {picked[-1]['dcr'] if picked else '-'}).\n"
            f"Past the {GRACE}-day grace period and ready for your approval: {len(ready)} titles, {gb(rb)}.\n"
            f"Plex Janitor: {jstat}. Watchlists: {wl_status}.\n"
            + ''.join(f"- {i['title']} ({i['year']}) {gb(i['bytes'])} DCR {i['dcr']}\n" for i in ready[:15])
            + ("Nothing is deleted until you approve it in the Plex project." if ready else ""))
    log(body.replace('\n', ' | '))
    if not DRY or env('PUSH_IN_DRY_RUN') == '1':
        push(('[dry run] ' if DRY else '') + 'Plex cleanup (DCR) weekly', body, env('REPORT_URL') or 'https://app.plex.tv/desktop')
    if jstat.startswith('FAILED'):
        push('Plex cleanup (DCR) failed', f'Plex Janitor sync failed: {jstat}. Check /var/log/plex-dcr.log on the Plex box.', 'https://plex-janitor.n8io.com')
        sys.exit(1)

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        log(f'ERROR: {e}')
        push('Plex cleanup (DCR) failed', f'The weekly DCR job crashed: {e}. Check /var/log/plex-dcr.log on the Plex box.', 'https://app.plex.tv/desktop')
        raise
