#!/usr/bin/env python3
"""Quarterly Plex account-sharing audit. READ-ONLY: it never changes Plex, Tautulli or any account.

Reads play history (with client IPs) from Tautulli, looks each IP up in local DB-IP lite
databases (IPs are never sent to any web API), groups each user's plays into "homes", and
emails Nate a report of accounts that look shared with another household.

Method (first run by hand 2026-11-18, thread "Detect Plex account sharing"):
  1. Every IP is classed as mobile (cellular carrier), vpn (VPN / relay / hosting) or home.
     Mobile and VPN plays are normal (people watch on their phones) and never flag anyone.
  2. A home "network" is an IPv4 address or an IPv6 /56. Networks are merged into one HOME when the
     same TV-type device (Roku, Apple TV, Fire TV, smart TV, console...) plays on both. That turns
     ISP IP changes, IPv4/IPv6 pairs and house moves (the TV sticks move with you) into one home.
  3. A home with a TV-type device, at least MIN_HOME_PLAYS plays and active over more than
     TRIP_DAYS days is a "real" home. Shorter ones are trips (vacation rental, hotel, relatives).
  4. FLAG a user when two real homes were both active over the same OVERLAP_DAYS or more, or when
     two different homes streamed at the same moment CONCURRENT_MIN times or more.
     A home change with no overlap and no shared device is listed as a NOTE (likely a move).
Runs on demand (Nate, 2026-11-20): a cron on the Plex box only sends a quarterly Pushbullet reminder
(--remind); Nate then asks Claude to run the audit. See README.md for the runbook.
"""
import argparse, collections, csv, datetime as dt, gzip, html, ipaddress, json, os, shutil, sys
import urllib.parse, urllib.request

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
            v = v[1:-1]
        os.environ.setdefault(k.strip(), v)

load_env(env('ENV_FILE', '/etc/plex-sharing-audit.env'))
STATE = env('STATE_DIR', '/var/lib/plex-sharing-audit')
LOG = env('LOG', '/var/log/plex-sharing-audit.log')
TAUTULLI = env('TAUTULLI_URL', 'https://plex-stats.n8io.com').rstrip('/')
LOOKBACK = int(env('LOOKBACK_DAYS', '180'))
MIN_HOME_PLAYS = int(env('MIN_HOME_PLAYS', '10'))
TRIP_DAYS = int(env('TRIP_DAYS', '14'))
OVERLAP_DAYS = int(env('OVERLAP_DAYS', '14'))
CONCURRENT_MIN = int(env('CONCURRENT_MIN', '3'))
NOW = dt.datetime.now(dt.timezone.utc)

# Cellular carriers (AS numbers). AT&T mixes home and mobile in AS7018, so its mobile ranges are listed.
MOBILE_ASN = {6167, 22394, 21928, 20057, 26599, 393486}   # Verizon Wireless, T-Mobile, AT&T Mobility, US Cellular...
MOBILE_NETS = [ipaddress.ip_network(n) for n in (
    '107.64.0.0/10', '166.128.0.0/9', '2600:380::/29',          # AT&T Mobility
    '172.32.0.0/11', '2607:fb90::/28',                           # T-Mobile
    '174.192.0.0/10', '2600:1000::/22')]       # Verizon Wireless
VPN_ASN = {13335, 212238, 4213, 9009, 60068, 20473, 14061, 16509, 14618, 15169, 396982, 8075,
           136787, 62240, 51852, 207137, 202422, 714, 6185, 36183}  # Cloudflare/WARP, VPN providers, clouds, iCloud Relay
PORTABLE_PRODUCTS = ('Plex for iOS', 'Plex for Android (Mobile)', 'Plex Web', 'Plex for Windows', 'Plex for Mac')

def log(msg):
    line = f"{NOW:%Y-%m-%dT%H:%M:%SZ} {msg}"
    print(line, file=sys.stderr)
    try:
        open(LOG, 'a').write(line + '\n')
    except OSError:
        pass

def http(url, method='GET', body=None, headers=None, timeout=60):
    h = dict(headers or {})
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        h.setdefault('Content-Type', 'application/json')
    h.setdefault('User-Agent', 'plex-sharing-audit')
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read() or b'null')

def push(title, body, url=None):
    tok = env('PUSHBULLET_TOKEN')
    log(f"PUSH: {title}: {body}")
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
def fetch_history():
    """Every play in the last LOOKBACK days from the Tautulli API, ungrouped."""
    key = env('TAUTULLI_API_KEY')
    if not key:
        raise SystemExit('TAUTULLI_API_KEY is not set')
    after = (NOW - dt.timedelta(days=LOOKBACK)).strftime('%Y-%m-%d')
    rows, start = [], 0
    while True:
        q = urllib.parse.urlencode({'apikey': key, 'cmd': 'get_history', 'grouping': 0, 'after': after,
                                    'start': start, 'length': 1000, 'order_column': 'started', 'order_dir': 'asc'})
        data = http(f"{TAUTULLI}/api/v2?{q}")['response']['data']
        batch = data.get('data') or []
        rows += batch
        start += len(batch)
        if not batch or start >= int(data.get('recordsFiltered') or 0):
            break
    return [{'user': r.get('friendly_name') or r.get('user'), 'user_id': str(r.get('user_id')),
             'ip': r.get('ip_address') or '', 'started': int(r.get('started') or 0),
             'stopped': int(r.get('stopped') or r.get('started') or 0), 'machine_id': r.get('machine_id') or '',
             'player': r.get('player') or '', 'platform': r.get('platform') or '', 'product': r.get('product') or '',
             'location': r.get('location') or ''} for r in rows]

def read_db(path):
    """A copy of tautulli.db (take it with sqlite3 .backup; never read the live file)."""
    import sqlite3
    db = sqlite3.connect(f'file:{path}?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    since = int((NOW - dt.timedelta(days=LOOKBACK)).timestamp())
    q = """SELECT sh.started, sh.stopped, sh.user_id, COALESCE(NULLIF(u.friendly_name, ''), u.username, sh.user) AS user,
                  sh.ip_address, sh.machine_id, sh.player, sh.platform, sh.product, sh.location
           FROM session_history sh LEFT JOIN users u ON u.user_id = sh.user_id WHERE sh.started >= ?"""
    return [{'user': r['user'], 'user_id': str(r['user_id']), 'ip': r['ip_address'] or '', 'started': int(r['started']),
             'stopped': int(r['stopped'] or r['started']), 'machine_id': r['machine_id'] or '', 'player': r['player'] or '',
             'platform': r['platform'] or '', 'product': r['product'] or '', 'location': r['location'] or ''}
            for r in db.execute(q, (since,))]

def read_csv(path):
    """Test input: the sessions.csv export made on 2026-11-18."""
    out = []
    for r in csv.DictReader(open(path)):
        out.append({'user': r.get('friendly_name') or r['username'], 'user_id': r['user_id'], 'ip': r['ip_address'],
                    'started': int(r['started']), 'stopped': int(r['stopped'] or r['started']),
                    'machine_id': r['machine_id'], 'player': r['player'], 'platform': r['platform'],
                    'product': r['product'], 'location': r['location']})
    return out

def geo_dbs():
    """Download this month's DB-IP lite city + ASN databases (CC BY 4.0) into STATE, keep last good copy."""
    os.makedirs(STATE, exist_ok=True)
    paths = {}
    for kind in ('city', 'asn'):
        path = os.path.join(STATE, f'dbip-{kind}-lite.mmdb')
        fresh = os.path.exists(path) and (NOW.timestamp() - os.path.getmtime(path)) < 20 * 86400
        if not fresh:
            for back in (0, 1):
                m = (NOW.replace(day=1) - dt.timedelta(days=back * 2)).strftime('%Y-%m')
                url = f'https://download.db-ip.com/free/dbip-{kind}-lite-{m}.mmdb.gz'
                try:
                    req = urllib.request.Request(url, headers={'User-Agent': 'curl/8.5.0'})  # db-ip.com 403s Python's UA
                    with urllib.request.urlopen(req, timeout=300) as r, open(path + '.tmp', 'wb') as f:
                        shutil.copyfileobj(gzip.GzipFile(fileobj=r), f)
                    os.replace(path + '.tmp', path)
                    break
                except Exception as e:
                    log(f"geo download {url}: {e}")
        if not os.path.exists(path):
            raise SystemExit(f'no {kind} database')
        paths[kind] = path
    return paths

class Geo:
    def __init__(self, geo_csv=None):
        self.cache = {}
        if geo_csv:
            for r in csv.DictReader(open(geo_csv)):
                self.cache[r['ip']] = {'asn': int(r['asn'] or 0), 'org': r['as_org'], 'city': r['city'],
                                       'region': r['region'], 'country': r['country']}
            return
        import maxminddb
        p = geo_dbs()
        self.city, self.asn = maxminddb.open_database(p['city']), maxminddb.open_database(p['asn'])

    def __call__(self, ip):
        if ip in self.cache:
            return self.cache[ip]
        c, a = self.city.get(ip) or {}, self.asn.get(ip) or {}
        sub = (c.get('subdivisions') or [{}])[0]
        g = {'asn': a.get('autonomous_system_number') or 0, 'org': a.get('autonomous_system_organization') or '?',
             'city': (c.get('city') or {}).get('names', {}).get('en', '?'),
             'region': sub.get('names', {}).get('en', ''), 'country': (c.get('country') or {}).get('iso_code', '')}
        self.cache[ip] = g
        return g

# ---------- analysis ----------
def ip_kind(ip, g):
    try:
        a = ipaddress.ip_address(ip)
    except ValueError:
        return 'unknown'
    if a.is_private or a.is_loopback or a.is_link_local:
        return 'lan'
    if g['asn'] in MOBILE_ASN or any(a in n for n in MOBILE_NETS if n.version == a.version):
        return 'mobile'
    if g['asn'] in VPN_ASN:
        return 'vpn'
    return 'home'

def net_key(ip):
    a = ipaddress.ip_address(ip)
    return str(ipaddress.ip_network(f'{ip}/56', strict=False)) if a.version == 6 else ip

def is_tv(p):
    return p['product'] not in PORTABLE_PRODUCTS

def day(t):
    return dt.datetime.fromtimestamp(t, dt.timezone.utc).strftime('%Y-%m-%d')

def analyze(plays, geo):
    by_user = collections.defaultdict(list)
    for p in plays:
        if p['ip']:
            by_user[(p['user_id'], p['user'])].append(p)
    results = []
    for (uid, user), ps in by_user.items():
        ps.sort(key=lambda p: p['started'])
        kinds = collections.Counter()
        parent = {}

        def find(x):
            while parent.setdefault(x, x) != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        tv_nets = collections.defaultdict(set)
        for p in ps:
            g = geo(p['ip'])
            p['kind'] = 'lan' if p['location'] == 'lan' else ip_kind(p['ip'], g)
            p['geo'] = g
            kinds[p['kind']] += 1
            if p['kind'] == 'home':
                p['net'] = net_key(p['ip'])
                find(p['net'])
                if is_tv(p):
                    tv_nets[p['machine_id']].add(p['net'])
        for nets in tv_nets.values():           # same TV device on two networks = same home
            nets = list(nets)
            for n in nets[1:]:
                parent[find(n)] = find(nets[0])
        homes = collections.defaultdict(lambda: {'plays': [], 'tv': set(), 'devices': set(), 'places': collections.Counter(),
                                                 'isps': {}, 'ips': set()})
        for p in ps:
            if p['kind'] != 'home':
                continue
            h = homes[find(p['net'])]
            p['home'] = find(p['net'])
            h['plays'].append(p)
            h['devices'].add(p['player'])
            h['ips'].add(p['ip'])
            if is_tv(p):
                h['tv'].add(p['player'])
            # one "place" per ISP + state (city names from IP data wobble between suburbs)
            isp = (p['geo']['org'], p['geo']['region'])
            h['isps'].setdefault(isp, f"{p['geo']['city']}, {p['geo']['region']} ({p['geo']['org']})")
            h['places'][isp] += 1
            p['loc'] = (p['home'], isp)
        hl = []
        for k, h in homes.items():
            first, last = h['plays'][0]['started'], h['plays'][-1]['started']
            span = (last - first) / 86400
            real = bool(h['tv']) and len(h['plays']) >= MIN_HOME_PLAYS and span > TRIP_DAYS
            hl.append({'key': k, 'n': len(h['plays']), 'first': first, 'last': last, 'span': span, 'real': real,
                       'tv': sorted(h['tv']), 'devices': sorted(h['devices']), 'ips': sorted(h['ips']),
                       'nplaces': len(h['places']),
                       'place': ', then '.join(h['isps'][i] for i in h['isps'] if h['places'][i] >= 3 or len(h['places']) == 1)})
        hl.sort(key=lambda h: -h['n'])
        # concurrent streams from two different homes
        conc = []
        hp = [p for p in ps if p['kind'] == 'home']
        for i, a in enumerate(hp):
            for b in hp[i + 1:]:
                if b['started'] >= a['stopped']:
                    break
                if a['loc'] != b['loc']:     # different home, or same home at a different ISP/state
                    conc.append((a, b))
        reasons, notes = [], []
        real = [h for h in hl if h['real']]
        for i, a in enumerate(real):
            for b in real[i + 1:]:
                ov = (min(a['last'], b['last']) - max(a['first'], b['first'])) / 86400
                if ov >= OVERLAP_DAYS:
                    reasons.append(f"two homes active at the same time for {ov:.0f} days ({day(max(a['first'], b['first']))} to "
                                   f"{day(min(a['last'], b['last']))}): {a['place']} [{', '.join(a['tv'][:5])}] and "
                                   f"{b['place']} [{', '.join(b['tv'][:5])}], no device seen at both")
                else:
                    old, new = sorted((a, b), key=lambda h: h['first'])
                    notes.append(f"home changed around {day(old['last'])} to {day(new['first'])}: {old['place']} then "
                                 f"{new['place']} with no shared TV device (likely a move or new TVs)")
        # a TV stick carried between two households merges them into one "home"; catch that too:
        # inside one home, two ISP/state places both busy over the same weeks is not a move
        for h in hl:
            locs = collections.defaultdict(list)
            for p in homes[h['key']]['plays']:
                locs[p['loc'][1]].append(p['started'])
            big = [(k, v[0], v[-1]) for k, v in locs.items()
                   if len(v) >= MIN_HOME_PLAYS and (v[-1] - v[0]) / 86400 > TRIP_DAYS]
            for i, (ka, fa, la) in enumerate(big):
                for kb, fb, lb in big[i + 1:]:
                    ov = (min(la, lb) - max(fa, fb)) / 86400
                    if ov >= OVERLAP_DAYS:
                        reasons.append(f"one TV device was used at two different connections that were both busy for {ov:.0f} "
                                       f"days ({day(max(fa, fb))} to {day(min(la, lb))}): {homes[h['key']]['isps'][ka]} and "
                                       f"{homes[h['key']]['isps'][kb]}")
        if len(conc) >= CONCURRENT_MIN:
            reasons.append(f"{len(conc)} streams from two different home connections at the same moment, e.g. "
                           + '; '.join(f"{dt.datetime.fromtimestamp(a['started'], dt.timezone.utc):%Y-%m-%d %H:%M}Z "
                                       f"{a['geo']['city']} ({a['player']}) + {b['geo']['city']} ({b['player']})"
                                       for a, b in conc[:3]))
        for h in hl:
            if not h['real'] and h['tv'] and h is not hl[0] and h['n'] >= 5:
                notes.append(f"short stay {day(h['first'])} to {day(h['last'])}, {h['n']} plays at {h['place']} on "
                             f"{', '.join(h['tv'][:3])} (trip)")
        for h in hl:
            if h['real'] and h['nplaces'] > 1 and ', then ' in h['place'] and not any(r.startswith('one TV device') for r in reasons):
                notes.append(f"one home seen at more than one ISP or state ({h['place']}); the same TV device "
                             "played at each, so most likely a move, not sharing")
        results.append({'user': user, 'user_id': uid, 'plays': len(ps), 'kinds': dict(kinds), 'homes': hl,
                        'real_homes': len(real), 'concurrent': len(conc), 'flag': bool(reasons),
                        'reasons': reasons, 'notes': notes, 'devices': len({p['machine_id'] for p in ps})})
    results.sort(key=lambda r: (not r['flag'], -len(r['notes']), -r['plays']))
    return results

# ---------- report ----------
def render(results, nplays):
    since = (NOW - dt.timedelta(days=LOOKBACK)).strftime('%Y-%m-%d')
    flagged = [r for r in results if r['flag']]
    noted = [r for r in results if not r['flag'] and r['notes']]
    e = html.escape
    tl = lambda r: f"{TAUTULLI}/user?user_id={r['user_id']}"
    subject = f"Plex sharing audit {NOW:%Y-%m-%d}: " + (f"{len(flagged)} account(s) look shared" if flagged else "nothing suspicious")
    t = [subject, f"Plays {since} to {NOW:%Y-%m-%d}: {nplays} from {len(results)} users. Mobile/VPN plays count as normal.", '']
    h = [f"<h2>{e(subject)}</h2><p>Plays {since} to {NOW:%Y-%m-%d}: {nplays} from {len(results)} users. "
         "Phones on cellular and VPNs count as normal; only TV-type devices at different home connections count.</p>"]
    t.append('LOOKS SHARED' if flagged else 'Nothing looks shared.')
    h.append('<h3>Looks shared</h3>' if flagged else '<p><b>Nothing looks shared.</b></p>')
    for r in flagged:
        t += [f"- {r['user']} ({tl(r)})"] + [f"    {x}" for x in r['reasons'] + r['notes']]
        h.append(f"<p><b><a href='{e(tl(r))}'>{e(r['user'])}</a></b></p><ul>" +
                 ''.join(f"<li>{e(x)}</li>" for x in r['reasons'] + r['notes']) + '</ul>')
    if noted:
        t += ['', 'LOOKED ODD, PROBABLY FINE']
        h.append('<h3>Looked odd, probably fine</h3>')
        for r in noted:
            t += [f"- {r['user']}"] + [f"    {x}" for x in r['notes']]
            h.append(f"<p><b><a href='{e(tl(r))}'>{e(r['user'])}</a></b></p><ul>" + ''.join(f"<li>{e(x)}</li>" for x in r['notes']) + '</ul>')
    t += ['', 'ALL USERS (plays: home / mobile / vpn, homes, TV devices)']
    h.append("<h3>All users</h3><table border='1' cellpadding='4' cellspacing='0' style='border-collapse:collapse;font-size:13px'>"
             "<tr><th>User</th><th>Plays</th><th>Home / mobile / VPN</th><th>Homes</th><th>Main home</th><th>TV devices there</th></tr>")
    for r in sorted(results, key=lambda r: -r['plays']):
        k = r['kinds']
        main = r['homes'][0] if r['homes'] else None
        row = [r['user'], r['plays'], f"{k.get('home', 0) + k.get('lan', 0)} / {k.get('mobile', 0)} / {k.get('vpn', 0)}",
               r['real_homes'], main['place'] if main else '-', ', '.join(main['tv'][:6]) if main else '-']
        t.append('- ' + ' | '.join(map(str, row)))
        h.append('<tr>' + ''.join(f"<td>{e(str(c))}</td>" for c in row) + '</tr>')
    h.append("</table><p style='color:#666;font-size:12px'>Read-only report from addons/plex-sharing-audit on the Plex box "
             "(n8io/plex-server). IP locations from DB-IP lite (CC BY 4.0, db-ip.com), looked up locally.</p>")
    return subject, '\n'.join(t), ''.join(h)

def email(subject, text, body):
    key, to = env('RESEND_API_KEY'), env('EMAIL_TO')
    if not key or not to:
        raise SystemExit('RESEND_API_KEY / EMAIL_TO not set')
    http('https://api.resend.com/emails', 'POST',
         {'from': env('EMAIL_FROM', 'N8Flix <n8flix-noreply@n8io.com>'), 'to': [x.strip() for x in to.split(',')],
          'subject': subject, 'text': text, 'html': body}, {'Authorization': f'Bearer {key}'})

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--remind', action='store_true', help='only send the quarterly Pushbullet reminder (cron on the Plex box)')
    ap.add_argument('--from-db', help='read plays from a copy of tautulli.db instead of the Tautulli API')
    ap.add_argument('--from-csv', help='test: read plays from a sessions.csv export instead of Tautulli')
    ap.add_argument('--geo-csv', help='test: ip,asn,as_org,city,region,country instead of the DB-IP databases')
    ap.add_argument('--no-email', action='store_true', help='print the report instead of emailing it')
    a = ap.parse_args()
    if a.remind:
        push('Plex sharing audit is due', 'Quarterly reminder: open the Claude thread "Detect Plex account sharing" '
             'and ask it to run the audit (runbook: addons/plex-sharing-audit/README.md).',
             env('REMIND_URL') or 'https://github.com/n8io/plex-server/tree/master/addons/plex-sharing-audit')
        return
    try:
        plays = read_db(a.from_db) if a.from_db else read_csv(a.from_csv) if a.from_csv else fetch_history()
        results = analyze(plays, Geo(a.geo_csv))
        subject, text, body = render(results, len(plays))
        os.makedirs(STATE, exist_ok=True)
        out = os.path.join(STATE, f"report-{NOW:%Y-%m-%d}")
        open(out + '.txt', 'w').write(text)
        open(out + '.html', 'w').write(body)
        os.chmod(out + '.txt', 0o600)
        os.chmod(out + '.html', 0o600)
        if a.no_email:
            print(text)
        else:
            email(subject, text, body)
        log(f"ok: {subject}; {len(plays)} plays; report {out}.txt")
    except BaseException as ex:
        if isinstance(ex, SystemExit) and ex.code in (0, None):
            raise
        log(f"FAILED: {ex!r}")
        push('Plex sharing audit failed', f"Reason: {ex!r}. Log: {LOG} on the Plex box.",
             'https://github.com/n8io/plex-server/tree/master/addons/plex-sharing-audit')
        raise

if __name__ == '__main__':
    main()
