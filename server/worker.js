/* EGO FOCUS push server — Cloudflare Worker + D1.
 * Stores only: a device id, the browser's push subscription, and upcoming reminder times
 * (with the task title only if the user allowed it). A cron runs every minute and sends
 * due reminders with standard Web Push (VAPID + aes128gcm), using WebCrypto only. */

const ALLOWED_ORIGINS = ['https://egiz3095.github.io'];
const MAX_REMINDERS = 300;
const enc = new TextEncoder();

// ---------- base64url ----------
export function b64u(bytes) {
  let s = ''; const b = new Uint8Array(bytes);
  for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
export function unb64u(str) {
  const s = str.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((str.length + 3) % 4);
  const bin = atob(s); const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
const concat = (...arrs) => { const n = arrs.reduce((a, b) => a + b.length, 0); const o = new Uint8Array(n); let p = 0; for (const a of arrs) { o.set(a, p); p += a.length; } return o; };

// ---------- VAPID keys (generated once, kept in D1) ----------
async function getVapid(env) {
  const row = await env.DB.prepare('SELECT v FROM config WHERE k = ?').bind('vapid').first();
  if (row) return JSON.parse(row.v);
  const kp = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const jwk = await crypto.subtle.exportKey('jwk', kp.privateKey);
  const pub = new Uint8Array(await crypto.subtle.exportKey('raw', kp.publicKey));
  const vapid = { jwk, publicKey: b64u(pub) };
  await env.DB.prepare('INSERT OR IGNORE INTO config (k, v) VALUES (?, ?)').bind('vapid', JSON.stringify(vapid)).run();
  const again = await env.DB.prepare('SELECT v FROM config WHERE k = ?').bind('vapid').first();
  return JSON.parse(again.v);
}

export async function vapidAuthHeader(endpoint, vapid, subject) {
  const aud = new URL(endpoint).origin;
  const header = b64u(enc.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const claims = b64u(enc.encode(JSON.stringify({ aud, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: subject })));
  const key = await crypto.subtle.importKey('jwk', vapid.jwk, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(header + '.' + claims)));
  return `vapid t=${header}.${claims}.${b64u(sig)}, k=${vapid.publicKey}`;
}

// ---------- RFC 8291 payload encryption (aes128gcm) ----------
async function hkdf(salt, ikm, info, length) {
  const key = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info }, key, length * 8));
}

export async function encryptPayload(payload, p256dhB64, authB64, saltOverride, localKeysOverride) {
  const uaPublic = unb64u(p256dhB64), authSecret = unb64u(authB64);
  const local = localKeysOverride || await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const asPublic = new Uint8Array(await crypto.subtle.exportKey('raw', local.publicKey));
  const uaKey = await crypto.subtle.importKey('raw', uaPublic, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey }, local.privateKey, 256));
  const ikm = await hkdf(authSecret, shared, concat(enc.encode('WebPush: info\0'), uaPublic, asPublic), 32);
  const salt = saltOverride || crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(salt, ikm, enc.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(salt, ikm, enc.encode('Content-Encoding: nonce\0'), 12);
  const aes = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['encrypt']);
  const plain = concat(enc.encode(payload), new Uint8Array([2]));
  const cipher = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, aes, plain));
  const rs = new Uint8Array([0, 0, 0x10, 0]); // 4096
  return concat(salt, rs, new Uint8Array([asPublic.length]), asPublic, cipher);
}

async function sendPush(env, vapid, device, message) {
  const body = await encryptPayload(JSON.stringify(message), device.p256dh, device.auth);
  const auth = await vapidAuthHeader(device.endpoint, vapid, env.VAPID_SUBJECT || 'https://egiz3095.github.io/EGO-FOCUS/web/');
  const res = await fetch(device.endpoint, {
    method: 'POST',
    headers: { 'Content-Encoding': 'aes128gcm', 'Content-Type': 'application/octet-stream', TTL: '3600', Urgency: 'high', Authorization: auth },
    body
  });
  return res.status;
}

// ---------- HTTP API ----------
function cors(req) {
  const origin = req.headers.get('Origin') || '';
  return {
    'Access-Control-Allow-Origin': ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0],
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400', Vary: 'Origin'
  };
}
const json = (req, data, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json', ...cors(req) } });
const validId = id => typeof id === 'string' && /^[A-Za-z0-9-]{16,64}$/.test(id);

async function handle(req, env) {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors(req) });
  const url = new URL(req.url);
  if (req.method === 'GET' && url.pathname === '/vapid') return json(req, { publicKey: (await getVapid(env)).publicKey });
  if (req.method === 'GET' && url.pathname === '/health') return json(req, { ok: true });
  if (req.method !== 'POST') return json(req, { error: 'not found' }, 404);

  let data; try { data = await req.json(); } catch (e) { return json(req, { error: 'bad json' }, 400); }
  if (!validId(data.deviceId)) return json(req, { error: 'bad device' }, 400);
  const now = Date.now();

  if (url.pathname === '/subscribe') {
    const s = data.subscription || {};
    if (typeof s.endpoint !== 'string' || !/^https:\/\//.test(s.endpoint) || !s.keys?.p256dh || !s.keys?.auth) return json(req, { error: 'bad subscription' }, 400);
    await env.DB.prepare(`INSERT INTO devices (id, endpoint, p256dh, auth, updated_at) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET endpoint = excluded.endpoint, p256dh = excluded.p256dh, auth = excluded.auth, updated_at = excluded.updated_at`)
      .bind(data.deviceId, s.endpoint, s.keys.p256dh, s.keys.auth, now).run();
    return json(req, { ok: true });
  }
  if (url.pathname === '/sync') {
    const list = Array.isArray(data.reminders) ? data.reminders.slice(0, MAX_REMINDERS) : [];
    const stmts = [env.DB.prepare('DELETE FROM reminders WHERE device_id = ?').bind(data.deviceId)];
    for (const r of list) {
      const at = Number(r.at);
      if (!Number.isFinite(at) || at < now - 60000 || at > now + 62 * 86400000) continue;
      stmts.push(env.DB.prepare('INSERT OR REPLACE INTO reminders (device_id, rid, fire_at, title, body) VALUES (?, ?, ?, ?, ?)')
        .bind(data.deviceId, String(r.id).slice(0, 120), at, String(r.title || 'EGO FOCUS').slice(0, 120), String(r.body || 'لديك تذكير').slice(0, 300)));
    }
    await env.DB.batch(stmts);
    return json(req, { ok: true, stored: stmts.length - 1 });
  }
  if (url.pathname === '/test') {
    const device = await env.DB.prepare('SELECT * FROM devices WHERE id = ?').bind(data.deviceId).first();
    if (!device) return json(req, { error: 'not subscribed' }, 404);
    const status = await sendPush(env, await getVapid(env), device, { title: 'EGO FOCUS', body: 'تنبيه تجريبي من الخادم — سيصلك التذكير حتى والتطبيق مغلق.' });
    return json(req, { ok: status < 300, status });
  }
  if (url.pathname === '/unsubscribe') {
    await env.DB.batch([env.DB.prepare('DELETE FROM reminders WHERE device_id = ?').bind(data.deviceId),
      env.DB.prepare('DELETE FROM devices WHERE id = ?').bind(data.deviceId)]);
    return json(req, { ok: true });
  }
  return json(req, { error: 'not found' }, 404);
}

// ---------- Cron: send due reminders ----------
async function sendDue(env) {
  const now = Date.now();
  const due = await env.DB.prepare(`SELECT r.device_id, r.rid, r.title, r.body, d.endpoint, d.p256dh, d.auth
    FROM reminders r JOIN devices d ON d.id = r.device_id WHERE r.fire_at <= ? AND r.fire_at > ? LIMIT 500`).bind(now + 20000, now - 15 * 60000).all();
  if (!due.results.length) { await env.DB.prepare('DELETE FROM reminders WHERE fire_at <= ?').bind(now - 15 * 60000).run(); return 0; }
  const vapid = await getVapid(env);
  const gone = new Set(), sent = [];
  for (const r of due.results) {
    if (gone.has(r.device_id)) continue;
    try {
      const status = await sendPush(env, vapid, r, { title: r.title, body: r.body, tag: r.rid });
      if (status === 404 || status === 410) gone.add(r.device_id);
    } catch (e) { /* retry next minute while within the window */ continue; }
    sent.push(env.DB.prepare('DELETE FROM reminders WHERE device_id = ? AND rid = ?').bind(r.device_id, r.rid));
  }
  for (const id of gone) {
    sent.push(env.DB.prepare('DELETE FROM reminders WHERE device_id = ?').bind(id), env.DB.prepare('DELETE FROM devices WHERE id = ?').bind(id));
  }
  sent.push(env.DB.prepare('DELETE FROM reminders WHERE fire_at <= ?').bind(now - 15 * 60000));
  await env.DB.batch(sent);
  return due.results.length;
}

export default {
  async fetch(req, env) {
    try { return await handle(req, env); } catch (e) { return json(req, { error: 'server error' }, 500); }
  },
  async scheduled(event, env, ctx) { ctx.waitUntil(sendDue(env)); }
};
