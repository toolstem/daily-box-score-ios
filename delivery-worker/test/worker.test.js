import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

import { makeStore } from '../src/store.js';
import { logSender, buildMime, sigV4 } from '../src/senders.js';
import { checkEntitlement, notificationTransaction } from '../src/apple.js';
import { normalizeEmail, normalizeUsPhone, base64url, sha256Hex } from '../src/util.js';
import {
  route, runDaily, remoteFlags, channelAllowed, smsKeyword, fetchOwn, unsubscribeUrl, newestPaperDate,
} from '../src/index.js';

// ---------- fakes ----------

function fakeD1() {
  const db = new DatabaseSync(':memory:');
  db.exec(readFileSync(new URL('../migrations/0001_init.sql', import.meta.url), 'utf8'));
  return {
    prepare(sql) {
      const st = db.prepare(sql);
      let args = [];
      const api = {
        bind(...a) { args = a.map((v) => (v === undefined ? null : v)); return api; },
        async first() { return st.get(...args) ?? null; },
        async all() { return { results: st.all(...args) }; },
        async run() { const r = st.run(...args); return { success: true, meta: { changes: Number(r.changes) } }; },
      };
      return api;
    },
  };
}

const te = new TextEncoder();
const jws = (payload) => `e30.${base64url(te.encode(JSON.stringify(payload)))}.sig`;

async function pem() {
  const k = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign']);
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', k.privateKey));
  return `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`;
}

const NOW = Date.parse('2026-11-24T15:00:00Z'); // 9:00 a.m. Central
const DAY = 86400000;

function fakeFetch(routes) {
  const calls = [];
  const fn = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    const h = routes[String(url)];
    if (!h) return new Response('nope', { status: 404 });
    const r = typeof h === 'function' ? h(url, init) : h;
    if (r instanceof Response) return r;
    if (r instanceof Uint8Array) return new Response(r, { status: 200 });
    return new Response(typeof r === 'string' ? r : JSON.stringify(r), { status: 200 });
  };
  fn.calls = calls;
  return fn;
}

const CFG_ON = { archive_pass: { mode: 'paid', mlb_features: 'paid' }, delivery: { email_enabled: true, sms_enabled: false } };
const PDF = te.encode('%PDF-1.4 fake paper');

function appleRoutes({ txid = '2000000111', active = true, product = 'com.omcollective.footballboxscores.archivepass.yearly', bundle = 'com.omcollective.footballboxscores' } = {}) {
  const tx = { originalTransactionId: txid, productId: product, bundleId: bundle, type: 'Auto-Renewable Subscription', expiresDate: NOW + 300 * DAY };
  return {
    [`https://api.storekit.itunes.apple.com/inApps/v1/transactions/${txid}`]: { signedTransactionInfo: jws(tx) },
    [`https://api.storekit.itunes.apple.com/inApps/v1/subscriptions/${txid}`]: {
      data: [{ lastTransactions: [{ originalTransactionId: txid, status: active ? 1 : 2, signedTransactionInfo: jws(tx) }] }],
    },
  };
}

async function setup(extraRoutes = {}, envOver = {}) {
  const env = {
    EMAIL_ENABLED: 'true', SMS_ENABLED: 'false', EMAIL_PROVIDER: 'log',
    PUBLIC_BASE_URL: 'https://delivery.toolstem.com', POSTAL_ADDRESS: 'OM Collective LLC, PO Box 1, Austin TX',
    LINK_SECRET: 'test-secret-test-secret-test-secret', APPLE_ISSUER_ID: 'iss', APPLE_KEY_ID: 'kid',
    APPLE_PRIVATE_KEY: await pem(), ...envOver,
  };
  const fetchFn = fakeFetch({
    'https://www.toolstem.com/football-box-scores/app_config.json': CFG_ON,
    'https://www.toolstem.com/daily-box-score/feed/app_config.json': CFG_ON,
    'https://www.toolstem.com/football-box-scores/feed_index.json': { editions: [{ date: '2026-11-23' }, { date: '2026-11-22' }] },
    'https://www.toolstem.com/football-box-scores/nfl_boxscores_2026-11-23.pdf': PDF,
    'https://www.toolstem.com/daily-box-score/feed/editions.json': { editions: [{ date: '2026-10-28' }] },
    ...appleRoutes(),
    ...extraRoutes,
  });
  const email = logSender();
  const d = { store: makeStore(fakeD1()), now: NOW, fetchFn, email };
  return { env, d, email, fetchFn };
}

const post = (path, body, headers = {}) =>
  new Request(`https://delivery.toolstem.com${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'cf-connecting-ip': '1.2.3.4', ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });

// Capture confirm tokens by wrapping the log sender.
function captureTokens(email) {
  const tokens = [];
  const orig = email.send;
  email.send = async (msg) => {
    const m = /\/v1\/confirm\?t=([A-Za-z0-9_-]+)/.exec(msg.text);
    if (m) tokens.push(m[1]);
    email.last = msg;
    return orig(msg);
  };
  return tokens;
}

// ---------- unit ----------

test('email and phone normalisation', () => {
  assert.equal(normalizeEmail('  Fan@Example.COM '), 'fan@example.com');
  assert.equal(normalizeEmail('bad'), null);
  assert.equal(normalizeEmail('a@b.com\r\nBcc: x@y.com'), null);
  assert.equal(normalizeEmail('<a@b.com>'), null);
  assert.equal(normalizeUsPhone('(512) 555-0123'), '+15125550123');
  assert.equal(normalizeUsPhone('+1 512 555 0123'), '+15125550123');
  assert.equal(normalizeUsPhone('12345'), null);
  assert.equal(normalizeUsPhone('+44 20 7946 0958'), null);
});

test('remote flags: missing file or garbage means off', async () => {
  const none = fakeFetch({});
  assert.deepEqual(await remoteFlags('football', none), { email: false, sms: false, passMode: 'paid', mlb: 'paid' });
  const junk = fakeFetch({ 'https://www.toolstem.com/football-box-scores/app_config.json': '<html>' });
  assert.equal((await remoteFlags('football', junk)).email, false);
  const truthy = fakeFetch({ 'https://www.toolstem.com/football-box-scores/app_config.json': { delivery: { email_enabled: 'yes' } } });
  assert.equal((await remoteFlags('football', truthy)).email, false);
});

test('channelAllowed: both switches, pass kill and MLB kill', () => {
  const env = { EMAIL_ENABLED: 'true' };
  const on = { email: true, sms: false, passMode: 'paid', mlb: 'paid' };
  assert.equal(channelAllowed(env, 'football', on, 'email'), true);
  assert.equal(channelAllowed({ EMAIL_ENABLED: 'false' }, 'football', on, 'email'), false);
  assert.equal(channelAllowed(env, 'football', { ...on, email: false }, 'email'), false);
  assert.equal(channelAllowed(env, 'football', { ...on, passMode: 'off' }, 'email'), false);
  assert.equal(channelAllowed(env, 'baseball', { ...on, mlb: 'off' }, 'email'), false);
  assert.equal(channelAllowed(env, 'football', { ...on, mlb: 'off' }, 'email'), true);
  assert.equal(channelAllowed(env, 'football', on, 'sms'), false);
});

test('fetchOwn refuses other hosts and oversize bodies', async () => {
  await assert.rejects(fetchOwn('https://evil.example.com/x', 10, fakeFetch({})), /bad_host/);
  await assert.rejects(fetchOwn('http://www.toolstem.com/x', 10, fakeFetch({})), /bad_host/);
  const big = fakeFetch({ 'https://www.toolstem.com/x': 'x'.repeat(100) });
  await assert.rejects(fetchOwn('https://www.toolstem.com/x', 10, big), /too_big/);
});

test('Apple: tips, other apps and expired subs never count', async () => {
  const env = { APPLE_ISSUER_ID: 'i', APPLE_KEY_ID: 'k', APPLE_PRIVATE_KEY: await pem() };
  const ok = await checkEntitlement(env, 'football', '2000000111', fakeFetch(appleRoutes()), NOW);
  assert.equal(ok.active, true);
  const tip = await checkEntitlement(env, 'football', '2000000111',
    fakeFetch(appleRoutes({ product: 'com.omcollective.footballboxscores.tip.small' })), NOW);
  assert.equal(tip, null);
  const other = await checkEntitlement(env, 'football', '2000000111',
    fakeFetch(appleRoutes({ bundle: 'com.someone.else' })), NOW);
  assert.equal(other, null);
  const expired = await checkEntitlement(env, 'football', '2000000111', fakeFetch(appleRoutes({ active: false })), NOW);
  assert.equal(expired.active, false);
  assert.equal(await checkEntitlement(env, 'football', 'abc', fakeFetch({}), NOW), null);
});

test('notification payload is only a pointer', () => {
  const body = { signedPayload: jws({ notificationType: 'REFUND', data: { bundleId: 'com.omcollective.footballboxscores', signedTransactionInfo: jws({ originalTransactionId: '2000000111' }) } }) };
  assert.deepEqual(notificationTransaction(body), { app: 'football', transactionId: '2000000111', type: 'REFUND' });
  assert.equal(notificationTransaction({ signedPayload: 'junk' }), null);
});

test('MIME has unsubscribe headers and a PDF part', () => {
  const mime = buildMime('Paper <paper@toolstem.com>', {
    to: 'fan@example.com', subject: 'S', text: 't', html: '<p>h</p>',
    unsubscribeUrl: 'https://delivery.toolstem.com/v1/unsubscribe?u=1&t=2',
    attachment: { filename: 'p.pdf', bytes: PDF },
  }, 'seed');
  assert.match(mime, /List-Unsubscribe: <https:\/\/delivery\.toolstem\.com/);
  assert.match(mime, /List-Unsubscribe-Post: List-Unsubscribe=One-Click/);
  assert.match(mime, /Content-Type: application\/pdf; name="p.pdf"/);
});

test('SigV4 signs deterministically', async () => {
  const env = { AWS_REGION: 'us-east-1', AWS_ACCESS_KEY_ID: 'AKID', AWS_SECRET_ACCESS_KEY: 'secret' };
  const h1 = await sigV4(env, 'email.us-east-1.amazonaws.com', '/v2/email/outbound-emails', '{}', new Date(NOW));
  const h2 = await sigV4(env, 'email.us-east-1.amazonaws.com', '/v2/email/outbound-emails', '{}', new Date(NOW));
  assert.equal(h1.authorization, h2.authorization);
  assert.match(h1.authorization, /^AWS4-HMAC-SHA256 Credential=AKID\/20261124\/us-east-1\/ses\/aws4_request/);
});

// ---------- flows ----------

test('subscribe -> confirm -> daily send -> one-click unsubscribe', async () => {
  const { env, d, email } = await setup();
  const tokens = captureTokens(email);
  const res = await route(post('/v1/subscribe', { app: 'football', transactionId: '2000000111', email: 'Fan@Example.com' }), env, d);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.emailPending, true);
  assert.ok(body.manageToken.length >= 40);
  assert.equal(tokens.length, 1);

  // Nothing is sent before the confirm.
  let report = await runDaily(env, d);
  assert.equal(report.find((r) => r.app === 'football').sent, 0);
  assert.equal(email.sent.length, 1); // only the confirm email

  // GET shows a button only; POST confirms.
  const g = await route(new Request(`https://delivery.toolstem.com/v1/confirm?t=${tokens[0]}`), env, d);
  assert.match(await g.text(), /<form method="post"/);
  const c = await route(new Request('https://delivery.toolstem.com/v1/confirm', {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: `t=${tokens[0]}`,
  }), env, d);
  assert.equal(c.status, 200);

  report = await runDaily(env, d);
  const fb = report.find((r) => r.app === 'football');
  assert.equal(fb.sent, 1);
  assert.equal(email.last.to, 'fan@example.com');
  assert.ok(email.last.attachment);
  assert.match(email.last.text, /PO Box 1/);

  // Re-run: no double send.
  report = await runDaily(env, d);
  assert.equal(report.find((r) => r.app === 'football').sent, 0);

  // Status shows a masked address only.
  const st = await (await route(post('/v1/status', { app: 'football', manageToken: body.manageToken }), env, d)).json();
  assert.equal(st.email, 'f***@example.com');

  // One-click unsubscribe with a forged token fails, the real one works.
  const row = await d.store.byTransaction('football', '2000000111');
  const bad = await route(new Request(`https://delivery.toolstem.com/v1/unsubscribe?u=${row.id}&t=forged`, { method: 'POST' }), env, d);
  assert.equal(bad.status, 400);
  const url = await unsubscribeUrl(env, row.id);
  const u = await route(new Request(url, { method: 'POST', body: 'List-Unsubscribe=One-Click' }), env, d);
  assert.equal(u.status, 200);
  const after = await d.store.byTransaction('football', '2000000111');
  assert.ok(after.email_unsubscribed_at);
});

test('baseball delivery stops when the MLB kill switch is off', async () => {
  const { env, d } = await setup({
    'https://www.toolstem.com/daily-box-score/feed/app_config.json': { archive_pass: { mode: 'paid', mlb_features: 'off' }, delivery: { email_enabled: true } },
  });
  const res = await route(post('/v1/subscribe', { app: 'baseball', transactionId: '2000000111', email: 'a@b.com' }), env, d);
  assert.equal(res.status, 403);
  assert.equal((await res.json()).error, 'email_off');
});

test('no pass, no delivery; tips never qualify', async () => {
  const { env, d } = await setup(appleRoutes({ active: false }));
  const res = await route(post('/v1/subscribe', { app: 'football', transactionId: '2000000111', email: 'a@b.com' }), env, d);
  assert.equal(res.status, 403);
});

test('texts need explicit consent and stay off', async () => {
  const { env, d } = await setup();
  const res = await route(post('/v1/subscribe', { app: 'football', transactionId: '2000000111', phone: '5125550123' }), env, d);
  assert.equal(res.status, 403); // sms_off
  const { env: env2, d: d2 } = await setup({
    'https://www.toolstem.com/football-box-scores/app_config.json': { delivery: { email_enabled: true, sms_enabled: true } },
  }, { SMS_ENABLED: 'true' });
  const noConsent = await route(post('/v1/subscribe', { app: 'football', transactionId: '2000000111', phone: '5125550123' }), env2, d2);
  assert.equal((await noConsent.json()).error, 'sms_consent_required');
  const ok = await route(post('/v1/subscribe', { app: 'football', transactionId: '2000000111', phone: '5125550123', smsConsent: true, smsConsentVersion: 'v1' }), env2, d2);
  assert.equal((await ok.json()).smsPending, true);
});

test('STOP opts out and suppresses; HELP answers', async () => {
  const { d } = await setup();
  await d.store.insert({ id: 'r1', app: 'football', original_transaction_id: '1', product_id: 'p', entitlement: 'active', entitlement_checked_at: NOW, phone: '+15125550123', manage_hash: 'h', created_at: NOW, updated_at: NOW });
  assert.match(await smsKeyword(d.store, '+15125550123', ' stop ', NOW), /unsubscribed/);
  assert.ok((await d.store.byId('r1')).sms_opted_out_at);
  assert.equal(await d.store.isSuppressed(await sha256Hex('+15125550123')), true);
  assert.match(await smsKeyword(d.store, '+15125550123', 'HELP', NOW), /STOP/);
});

test('inbound SMS webhook refuses everything until a provider is wired', async () => {
  const { env, d } = await setup();
  const r = await route(post('/v1/sms/inbound', 'From=%2B15125550123&Body=STOP'), env, d);
  assert.equal(r.status, 403);
});

test('delete with the manage token removes the row', async () => {
  const { env, d } = await setup();
  const body = await (await route(post('/v1/subscribe', { app: 'football', transactionId: '2000000111', email: 'a@b.com' }), env, d)).json();
  assert.equal((await route(post('/v1/delete', { app: 'football', manageToken: 'wrong' }), env, d)).status, 404);
  assert.equal((await route(post('/v1/delete', { app: 'football', manageToken: body.manageToken }), env, d)).status, 200);
  assert.equal(await d.store.byTransaction('football', '2000000111'), null);
});

test('refund notification turns delivery off (re-checked with Apple)', async () => {
  const { env, d, email } = await setup();
  const tokens = captureTokens(email);
  await route(post('/v1/subscribe', { app: 'football', transactionId: '2000000111', email: 'a@b.com' }), env, d);
  await route(new Request('https://delivery.toolstem.com/v1/confirm', { method: 'POST', body: `t=${tokens[0]}`, headers: { 'content-type': 'application/x-www-form-urlencoded' } }), env, d);
  // Apple now says expired/revoked.
  Object.assign(d, { fetchFn: fakeFetch({ ...appleRoutes({ active: false }),
    'https://www.toolstem.com/football-box-scores/app_config.json': CFG_ON,
    'https://www.toolstem.com/football-box-scores/feed_index.json': { editions: [{ date: '2026-11-23' }] },
    'https://www.toolstem.com/football-box-scores/nfl_boxscores_2026-11-23.pdf': PDF }) });
  const note = { signedPayload: jws({ notificationType: 'REFUND', data: { bundleId: 'com.omcollective.footballboxscores', signedTransactionInfo: jws({ originalTransactionId: '2000000111' }) } }) };
  assert.equal((await route(post('/v1/apple/notifications', note), env, d)).status, 200);
  assert.equal((await d.store.byTransaction('football', '2000000111')).entitlement, 'inactive');
  const report = await runDaily(env, d);
  assert.equal(report.find((r) => r.app === 'football').sent, 0);
});

test('tripwire stops an anomalous run', async () => {
  const { env, d } = await setup({}, { MAX_RECIPIENTS_PER_RUN: '1' });
  for (const i of [1, 2]) {
    await d.store.insert({ id: `r${i}`, app: 'football', original_transaction_id: String(i), product_id: 'p', entitlement: 'active', entitlement_checked_at: NOW, email: `f${i}@example.com`, email_confirmed_at: NOW, manage_hash: `h${i}`, created_at: NOW, updated_at: NOW });
  }
  const report = await runDaily(env, d);
  const fb = report.find((r) => r.app === 'football');
  assert.equal(fb.skipped, 'tripwire');
  // Still stopped on the next tick.
  assert.equal((await runDaily(env, d)).find((r) => r.app === 'football').skipped, 'tripwire');
});

test('stale paper or delivery switched off: nothing sent', async () => {
  const { env, d } = await setup({}, { EMAIL_ENABLED: 'false' });
  assert.equal((await runDaily(env, d)).find((r) => r.app === 'football').skipped, 'email_off');
  const { env: e2, d: d2 } = await setup();
  // Baseball's newest paper is Oct 28: far older than 2 days.
  const bb = (await runDaily(e2, d2)).find((r) => r.app === 'baseball');
  assert.equal(bb.skipped, 'no_new_paper');
});

test('missing postal address blocks sending (CAN-SPAM)', async () => {
  const { env, d } = await setup({}, { POSTAL_ADDRESS: '' });
  assert.equal((await runDaily(env, d)).find((r) => r.app === 'football').skipped, 'missing_config');
});

test('before 7 a.m. Central nothing runs', async () => {
  const { env, d } = await setup();
  d.now = Date.parse('2026-11-24T11:30:00Z'); // 5:30 a.m. Central
  assert.deepEqual(await runDaily(env, d), [{ skipped: 'too_early' }]);
});

test('oversized and non-object bodies are rejected', async () => {
  const { env, d } = await setup();
  assert.equal((await route(post('/v1/subscribe', '[1]'), env, d)).status, 400);
  assert.equal((await route(post('/v1/subscribe', JSON.stringify({ app: 'football', pad: 'x'.repeat(5000) })), env, d)).status, 400);
});

// ---------- review round 2 ----------

async function confirmAll(env, d, tokens) {
  for (const t of tokens.splice(0)) {
    await route(new Request('https://delivery.toolstem.com/v1/confirm', {
      method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: `t=${t}`,
    }), env, d);
  }
}

test('kill switch typos stop delivery (fail closed)', async () => {
  for (const cfg of [
    { archive_pass: { mode: 'OFF' } },
    { archive_pass: { mode: 'disabled' } },
    { archive_pass: 'off' },
    { archive_pass: { mlb_features: 'Off' } },
  ]) {
    const f = fakeFetch({ 'https://www.toolstem.com/daily-box-score/feed/app_config.json': { ...cfg, delivery: { email_enabled: true } } });
    const flags = await remoteFlags('baseball', f);
    assert.equal(channelAllowed({ EMAIL_ENABLED: 'true' }, 'baseball', flags, 'email'), false, JSON.stringify(cfg));
  }
  const ok = fakeFetch({ 'https://www.toolstem.com/daily-box-score/feed/app_config.json': { archive_pass: { mode: 'Free' }, delivery: { email_enabled: true } } });
  assert.equal(channelAllowed({ EMAIL_ENABLED: 'true' }, 'baseball', await remoteFlags('baseball', ok), 'email'), true);
});

test('a big newest-first feed is read from the top only', async () => {
  const entries = [];
  for (let i = 0; i < 20000; i++) entries.push({ date: i === 0 ? '2026-10-28' : '1950-01-01', label: 'x'.repeat(200) });
  const big = JSON.stringify({ editions: entries });
  assert.ok(big.length > 4 * 1024 * 1024);
  const f = fakeFetch({ 'https://www.toolstem.com/daily-box-score/feed/editions.json': big });
  assert.equal(await newestPaperDate('baseball', f), '2026-10-28');
});

test('someone with only the transaction ID cannot take over a set-up row', async () => {
  const { env, d, email } = await setup();
  const tokens = captureTokens(email);
  const first = await (await route(post('/v1/subscribe', { app: 'football', transactionId: '2000000111', email: 'owner@example.com' }), env, d)).json();
  await confirmAll(env, d, tokens);

  // No token: status and phone changes refused, same email refused.
  const again = await route(post('/v1/subscribe', { app: 'football', transactionId: '2000000111', email: 'owner@example.com' }), env, d);
  assert.equal(again.status, 403);
  // A new email is allowed, but its token is dead until that email confirms.
  const intr = await (await route(post('/v1/subscribe', { app: 'football', transactionId: '2000000111', email: 'other@example.com' }), env, d)).json();
  const st = await route(post('/v1/status', { app: 'football', manageToken: intr.manageToken }), env, d);
  assert.equal(st.status, 404);
  // The owner's token still works.
  const own = await route(post('/v1/status', { app: 'football', manageToken: first.manageToken }), env, d);
  assert.equal(own.status, 200);
  // The owner keeps the same token on later saves.
  const keep = await (await route(post('/v1/subscribe', { app: 'football', transactionId: '2000000111', email: 'owner2@example.com', manageToken: first.manageToken }), env, d)).json();
  assert.equal(keep.manageToken, first.manageToken);
});

test('a confirm rate limit never strands the app token', async () => {
  const { env, d, email } = await setup();
  const tokens = captureTokens(email);
  const first = await (await route(post('/v1/subscribe', { app: 'football', transactionId: '2000000111', email: 'a1@example.com' }), env, d)).json();
  await confirmAll(env, d, tokens);
  let tok = first.manageToken;
  for (let i = 2; i <= 5; i++) {
    const r = await route(post('/v1/subscribe', { app: 'football', transactionId: '2000000111', email: `a${i}@example.com`, manageToken: tok }), env, d);
    const b = await r.json();
    if (r.status === 200) tok = b.manageToken;
  }
  const st = await route(post('/v1/status', { app: 'football', manageToken: tok }), env, d);
  assert.equal(st.status, 200);
});

test('a send cut off before it is recorded is never sent twice', async () => {
  const { env, d, email } = await setup();
  const tokens = captureTokens(email);
  await route(post('/v1/subscribe', { app: 'football', transactionId: '2000000111', email: 'fan@example.com' }), env, d);
  await confirmAll(env, d, tokens);
  const orig = d.store.finishDelivery;
  d.store.finishDelivery = async () => { throw new Error('worker killed'); };
  await assert.rejects(runDaily(env, d));
  d.store.finishDelivery = orig;
  const before = email.sent.length;
  await runDaily(env, d);
  assert.equal(email.sent.length, before);
});

test('START lifts a STOP', async () => {
  const store = makeStore(fakeD1());
  await smsKeyword(store, '+15125550123', 'STOP', NOW);
  assert.equal(await store.isSuppressed(await sha256Hex('+15125550123')), true);
  await smsKeyword(store, '+15125550123', 'start', NOW);
  assert.equal(await store.isSuppressed(await sha256Hex('+15125550123')), false);
});

test('billing grace period keeps delivery going', async () => {
  const txid = '2000000222';
  const tx = { originalTransactionId: txid, productId: 'com.omcollective.footballboxscores.archivepass.yearly', bundleId: 'com.omcollective.footballboxscores', type: 'Auto-Renewable Subscription', expiresDate: NOW - DAY };
  const f = fakeFetch({
    [`https://api.storekit.itunes.apple.com/inApps/v1/transactions/${txid}`]: { signedTransactionInfo: jws(tx) },
    [`https://api.storekit.itunes.apple.com/inApps/v1/subscriptions/${txid}`]: {
      data: [{ lastTransactions: [{ originalTransactionId: txid, status: 4, signedTransactionInfo: jws(tx), signedRenewalInfo: jws({ gracePeriodExpiresDate: NOW + 10 * DAY }) }] }],
    },
  });
  const env = { APPLE_ISSUER_ID: 'i', APPLE_KEY_ID: 'k', APPLE_PRIVATE_KEY: await pem() };
  const ent = await checkEntitlement(env, 'football', txid, f, NOW);
  assert.equal(ent.active, true);
  assert.equal(ent.expiresAt, NOW + 10 * DAY);
});

test('plain http is refused', async () => {
  const { env, d } = await setup();
  const r = await route(new Request('http://delivery.toolstem.com/v1/status', { method: 'POST', body: '{}' }), env, d);
  assert.equal(r.status, 403);
});
