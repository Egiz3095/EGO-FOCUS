import crypto from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import ece from 'http_ece';
import worker, { encryptPayload, vapidAuthHeader, b64u, unb64u } from './worker.mjs';
let pass = 0, fail = 0; const ok = (n, c) => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + n); };

// Fake browser subscription keys
const ua = crypto.createECDH('prime256v1'); ua.generateKeys();
const p256dh = b64u(ua.getPublicKey()), auth = b64u(crypto.randomBytes(16));
const decrypt = body => ece.decrypt(Buffer.from(body), { version: 'aes128gcm', privateKey: ua, authSecret: Buffer.from(unb64u(auth)) }).toString();

// 1) encryption round trip
const msg = JSON.stringify({ title: 'EGO FOCUS', body: 'حان الآن موعد: مراجعة الفواتير' });
ok('aes128gcm decrypts with http_ece', decrypt(await encryptPayload(msg, p256dh, auth)) === msg);

// 2) D1 shim on node:sqlite
const sql = new DatabaseSync(':memory:'); sql.exec(fs.readFileSync('../schema.sql', 'utf8'));
const stmt = (q, args = []) => ({ bind: (...a) => stmt(q, a), first: async () => sql.prepare(q).get(...args) ?? null,
  all: async () => ({ results: sql.prepare(q).all(...args) }), run: async () => sql.prepare(q).run(...args), _q: q, _a: args });
const env = { DB: { prepare: q => stmt(q), batch: async s => { for (const x of s) sql.prepare(x._q).run(...x._a); } } };

// capture outgoing pushes
const pushes = []; globalThis.fetch = async (url, init) => { pushes.push({ url, init }); return new Response(null, { status: 201 }); };
const call = (path, method = 'GET', body) => worker.fetch(new Request('https://w.example' + path, { method, headers: { 'Content-Type': 'application/json', Origin: 'https://egiz3095.github.io' }, body: body && JSON.stringify(body) }), env);

const v = await (await call('/vapid')).json(); ok('vapid public key 65 bytes', unb64u(v.publicKey).length === 65);
const v2 = await (await call('/vapid')).json(); ok('vapid key stable', v.publicKey === v2.publicKey);
const dev = crypto.randomUUID();
ok('subscribe', (await call('/subscribe', 'POST', { deviceId: dev, subscription: { endpoint: 'https://web.push.apple.com/abc', keys: { p256dh, auth } } })).status === 200);
ok('reject bad id', (await call('/subscribe', 'POST', { deviceId: 'x', subscription: {} })).status === 400);
const now = Date.now();
const r = await (await call('/sync', 'POST', { deviceId: dev, reminders: [
  { id: 'a|0', at: now - 1000, title: 'EGO FOCUS', body: 'حان الآن موعد: أ' },
  { id: 'b|15', at: now + 3600000, title: 'EGO FOCUS', body: 'بعد 15 دقيقة: ب' },
  { id: 'old', at: now - 86400000, title: 'x', body: 'x' } ] })).json();
ok('sync stores valid reminders only (2)', r.stored === 2);
ok('CORS header', (await call('/vapid')).headers.get('Access-Control-Allow-Origin') === 'https://egiz3095.github.io');

// 3) cron sends due reminder only
const waits = []; await worker.scheduled({}, env, { waitUntil: p => waits.push(p) }); await Promise.all(waits);
ok('one push sent', pushes.length === 1 && pushes[0].url === 'https://web.push.apple.com/abc');
const h = pushes[0].init.headers;
ok('push headers', h['Content-Encoding'] === 'aes128gcm' && h.TTL && h.Authorization.startsWith('vapid t='));
ok('push payload decrypts', JSON.parse(decrypt(new Uint8Array(pushes[0].init.body))).body === 'حان الآن موعد: أ');
// verify JWT signature with vapid public key
const [, t] = h.Authorization.match(/t=([^,]+)/); const [hd, cl, sg] = t.split('.');
const pub = await crypto.webcrypto.subtle.importKey('raw', unb64u(v.publicKey), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
ok('VAPID JWT signature valid', await crypto.webcrypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, pub, unb64u(sg), new TextEncoder().encode(hd + '.' + cl)));
ok('JWT aud = push origin', JSON.parse(Buffer.from(unb64u(cl)).toString()).aud === 'https://web.push.apple.com');
ok('sent reminder removed, future kept', sql.prepare('SELECT rid FROM reminders').all().map(x => x.rid).join() === 'b|15');
pushes.length = 0; await worker.scheduled({}, env, { waitUntil: p => waits.push(p) }); await Promise.all(waits);
ok('no duplicate on next cron', pushes.length === 0);
// 410 Gone removes device
globalThis.fetch = async () => new Response(null, { status: 410 });
sql.prepare('UPDATE reminders SET fire_at = ?').run(Date.now() - 1000);
await worker.scheduled({}, env, { waitUntil: p => waits.push(p) }); await Promise.all(waits);
ok('expired subscription cleaned up', sql.prepare('SELECT count(*) c FROM devices').get().c === 0);
console.log(pass + ' passed, ' + fail + ' failed'); process.exit(fail ? 1 : 0);
