// Plex Scan UI: browse libraries/items and trigger partial scans of their folders.
// Zero dependencies, Node 18+.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';
const PLEX_URL = (process.env.PLEX_URL || 'http://127.0.0.1:32400').replace(/\/$/, '');
const UI_USER = process.env.UI_USER || '';
const UI_PASS = process.env.UI_PASS || '';
const CLIENT_ID = 'plex-scan-ui';
let plexToken = process.env.PLEX_TOKEN || '';

const INDEX = fs.readFileSync(path.join(__dirname, 'public', 'index.html'));

async function signIn() {
  const { PLEX_USERNAME: login, PLEX_PASSWORD: password } = process.env;
  if (!login || !password) throw new Error('Set PLEX_TOKEN or PLEX_USERNAME + PLEX_PASSWORD');
  const res = await fetch('https://plex.tv/api/v2/users/signin', {
    method: 'POST',
    headers: { Accept: 'application/json', 'X-Plex-Client-Identifier': CLIENT_ID, 'X-Plex-Product': CLIENT_ID },
    body: new URLSearchParams({ login, password }),
  });
  if (!res.ok) throw new Error(`plex.tv sign-in failed: ${res.status}`);
  plexToken = (await res.json()).authToken;
}

async function plex(pathAndQuery, { method = 'GET', retry = true } = {}) {
  const res = await fetch(PLEX_URL + pathAndQuery, {
    method,
    headers: { Accept: 'application/json', 'X-Plex-Token': plexToken, 'X-Plex-Client-Identifier': CLIENT_ID },
  });
  if (res.status === 401 && retry && process.env.PLEX_USERNAME) {
    await signIn();
    return plex(pathAndQuery, { method, retry: false });
  }
  if (!res.ok) throw new Error(`Plex ${method} ${pathAndQuery.split('?')[0]} -> ${res.status}`);
  const text = await res.text();
  return text ? JSON.parse(text).MediaContainer : {};
}

const parentDir = (p) => p.replace(/[\\/][^\\/]*$/, '');
const partFiles = (items) => items.flatMap((m) => (m.Media || []).flatMap((md) => (md.Part || []).map((pt) => pt.file)));

// Folders Plex should scan for a given level. Partial scans are recursive.
async function scanTargets({ sectionId, ratingKey }) {
  if (!ratingKey) {
    const mc = await plex('/library/sections');
    const dir = (mc.Directory || []).find((d) => String(d.key) === String(sectionId));
    if (!dir) throw new Error(`Unknown library ${sectionId}`);
    return { sectionId: dir.key, paths: (dir.Location || []).map((l) => l.path) };
  }
  const meta = (await plex(`/library/metadata/${ratingKey}`)).Metadata?.[0];
  if (!meta) throw new Error(`Unknown item ${ratingKey}`);
  let paths = [];
  if (meta.type === 'show') {
    paths = (meta.Location || []).map((l) => l.path);
  } else if (meta.type === 'season') {
    paths = partFiles((await plex(`/library/metadata/${ratingKey}/children`)).Metadata || []).map(parentDir);
  } else {
    // movie, episode, track, etc: the folder holding the file(s)
    paths = partFiles([meta]).map(parentDir);
  }
  return { sectionId: meta.librarySectionID, paths: [...new Set(paths)] };
}

async function scan(body) {
  const { sectionId, paths } = await scanTargets(body);
  if (!paths.length) throw new Error('No folders found for that item');
  const results = [];
  for (const p of paths) {
    try {
      await plex(`/library/sections/${sectionId}/refresh?path=${encodeURIComponent(p)}`);
      results.push({ path: p, ok: true });
    } catch (e) {
      results.push({ path: p, ok: false, error: e.message });
    }
  }
  if (body.refreshMetadata && body.ratingKey) {
    try {
      await plex(`/library/metadata/${body.ratingKey}/refresh`, { method: 'PUT' });
      results.push({ path: '(metadata refresh)', ok: true });
    } catch (e) {
      results.push({ path: '(metadata refresh)', ok: false, error: e.message });
    }
  }
  return { sectionId, results };
}

const pick = (m) => ({
  ratingKey: m.ratingKey, key: m.key, type: m.type, title: m.title, year: m.year,
  index: m.index, parentIndex: m.parentIndex, childCount: m.childCount, leafCount: m.leafCount, thumb: m.thumb,
});

const routes = {
  'GET /api/libraries': async () =>
    ((await plex('/library/sections')).Directory || []).map((d) => ({
      key: d.key, title: d.title, type: d.type, refreshing: d.refreshing, paths: (d.Location || []).map((l) => l.path),
    })),
  'GET /api/items': async (q) => {
    const start = Number(q.get('start') || 0);
    const size = Math.min(Number(q.get('size') || 100), 500);
    const params = new URLSearchParams({ 'X-Plex-Container-Start': start, 'X-Plex-Container-Size': size, sort: 'titleSort' });
    if (q.get('title')) params.set('title', q.get('title'));
    const mc = await plex(`/library/sections/${encodeURIComponent(q.get('section'))}/all?${params}`);
    return { total: mc.totalSize ?? mc.size ?? 0, start, items: (mc.Metadata || []).map(pick) };
  },
  'GET /api/children': async (q) =>
    ((await plex(`/library/metadata/${encodeURIComponent(q.get('ratingKey'))}/children`)).Metadata || []).map(pick),
  // Folders on disk as Plex sees them (same API Plex Web uses for "Add folder").
  // Lets you scan a brand new show/movie folder that has no Plex item yet.
  'GET /api/folders': async (q) => {
    const dir = q.get('path');
    const mc = await plex(`/services/browse/${Buffer.from(dir).toString('base64')}?includeFiles=0`);
    return (mc.Path || []).map((p) => ({ path: p.path, title: p.title }));
  },
  'POST /api/scan-path': async (_q, { sectionId, path: p }) => {
    const lib = ((await plex('/library/sections')).Directory || []).find((d) => String(d.key) === String(sectionId));
    if (!lib) throw new Error(`Unknown library ${sectionId}`);
    if (!(lib.Location || []).some((l) => p === l.path || p.startsWith(l.path.replace(/\/?$/, '/')))) {
      throw new Error('Path is outside that library');
    }
    await plex(`/library/sections/${sectionId}/refresh?path=${encodeURIComponent(p)}`);
    return { sectionId, results: [{ path: p, ok: true }] };
  },
  'GET /api/targets': async (q) => scanTargets({ sectionId: q.get('section'), ratingKey: q.get('ratingKey') }),
  'POST /api/scan': async (_q, body) => scan(body),
  'GET /api/activity': async () =>
    ((await plex('/activities')).Activity || []).map((a) => ({ title: a.title, subtitle: a.subtitle, progress: a.progress, type: a.type })),
};

function authorized(req) {
  if (!UI_USER) return true;
  const [scheme, b64] = (req.headers.authorization || '').split(' ');
  if (scheme !== 'Basic' || !b64) return false;
  return Buffer.from(b64, 'base64').toString() === `${UI_USER}:${UI_PASS}`;
}

const send = (res, code, body, type = 'application/json') => {
  res.writeHead(code, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  res.end(type === 'application/json' ? JSON.stringify(body) : body);
};

http.createServer(async (req, res) => {
  if (req.url === '/healthz') return send(res, 200, { ok: true });
  if (!authorized(req)) {
    res.writeHead(401, { 'WWW-Authenticate': 'Basic realm="plex-scan-ui"' });
    return res.end();
  }
  const url = new URL(req.url, 'http://x');
  if (req.method === 'GET' && url.pathname === '/') return send(res, 200, INDEX, 'text/html; charset=utf-8');
  const handler = routes[`${req.method} ${url.pathname}`];
  if (!handler) return send(res, 404, { error: 'not found' });
  try {
    let body = {};
    if (req.method === 'POST') {
      let raw = '';
      for await (const chunk of req) raw += chunk;
      body = raw ? JSON.parse(raw) : {};
    }
    send(res, 200, await handler(url.searchParams, body));
  } catch (e) {
    console.error(e.message);
    send(res, 502, { error: e.message });
  }
}).listen(PORT, HOST, async () => {
  if (!plexToken) {
    try { await signIn(); } catch (e) { console.error(e.message); }
  }
  console.log(`plex-scan-ui on :${PORT} -> ${PLEX_URL}${UI_USER ? '' : ' (no UI auth set!)'}`);
});
