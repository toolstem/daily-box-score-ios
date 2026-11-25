// Box score paper delivery Worker.
//
// HTTP routes (all under PUBLIC_BASE_URL):
//   POST /v1/subscribe            app opt-in: email and/or phone, tied to a verified Apple purchase
//   POST /v1/status               app reads its own delivery status (manage token)
//   POST /v1/delete               app "Stop delivery and delete my address" (manage token)
//   GET|POST /v1/confirm          confirm-your-email link (GET shows a button; POST confirms)
//   GET|POST /v1/unsubscribe      signed link in every email; POST is RFC 8058 one-click
//   POST /v1/forget               signed link: delete everything
//   POST /v1/apple/notifications  App Store Server Notifications V2 (re-checked with Apple)
//   POST /v1/sms/inbound          STOP/HELP webhook (refuses everything until a provider is wired)
// Cron: the daily send, after the morning paper is published.
//
// Two independent off switches for sending: Worker env (EMAIL_ENABLED /
// SMS_ENABLED) AND the public app_config.json delivery flags. Both must
// be on. A missing or unreadable config file means OFF.

import { APPS, ALLOWED_FETCH_HOST, SMS_CONSENT } from './apps.js';
import { checkEntitlement, notificationTransaction } from './apple.js';
import { emailSender, smsSender } from './senders.js';
import { makeStore } from './store.js';
import {
  base64url, chicagoDate, daysBetween, escapeHtml, html, json,
  normalizeEmail, normalizeUsPhone, randomToken, sha256Hex,
} from './util.js';

const HOUR = 3600_000;
const DAY = 24 * HOUR;
const CONFIRM_TTL = 48 * HOUR;
const RETENTION_AFTER_LAPSE = 30 * DAY;

// ---------------------------------------------------------------- helpers

async function readCapped(res, maxBytes) {
  const declared = Number(res.headers.get('content-length') || 0);
  if (declared > maxBytes) throw new Error('too_big');
  const reader = res.body.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > maxBytes) {
      await reader.cancel();
      throw new Error('too_big');
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) {
    out.set(c, off);
    off += c.length;
  }
  return out;
}

/** GET from our own site only, no redirects off it, size-capped. */
export async function fetchOwn(url, maxBytes, fetchFn = fetch) {
  const u = new URL(url);
  if (u.protocol !== 'https:' || u.hostname !== ALLOWED_FETCH_HOST) throw new Error('bad_host');
  const res = await fetchFn(u.toString(), { redirect: 'manual', cf: { cacheTtl: 0 } });
  if (res.status !== 200) throw new Error(`status_${res.status}`);
  return readCapped(res, maxBytes);
}

/** Delivery flags from app_config.json. Anything unreadable = off. */
export async function remoteFlags(app, fetchFn = fetch) {
  const off = { email: false, sms: false, passMode: 'paid', mlb: 'paid' };
  try {
    const bytes = await fetchOwn(APPS[app].configUrl, 16 * 1024, fetchFn);
    const cfg = JSON.parse(new TextDecoder().decode(bytes));
    if (!cfg || typeof cfg !== 'object' || Array.isArray(cfg)) return off;
    const pass = cfg.archive_pass;
    const mode = (v) => (v === undefined ? 'paid' : ['paid', 'free', 'off'].includes(v) ? v : 'free');
    return {
      email: cfg.delivery?.email_enabled === true,
      sms: cfg.delivery?.sms_enabled === true,
      passMode: pass && typeof pass === 'object' ? mode(pass.mode) : pass === undefined ? 'paid' : 'free',
      mlb: pass && typeof pass === 'object' ? mode(pass.mlb_features) : 'paid',
    };
  } catch {
    return off;
  }
}

/** Both switches must be on, and the pass kill switch (plus MLB for baseball) must not be "off". */
export function channelAllowed(env, app, flags, channel) {
  const envOn = channel === 'email' ? env.EMAIL_ENABLED === 'true' : env.SMS_ENABLED === 'true';
  const remoteOn = channel === 'email' ? flags.email : flags.sms;
  if (!envOn || !remoteOn) return false;
  if (flags.passMode === 'off') return false;
  if (APPS[app].mlb && flags.mlb === 'off') return false;
  return true;
}

async function linkToken(env, purpose, id) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(env.LINK_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${purpose}:${id}`));
  return base64url(new Uint8Array(sig));
}

async function verifyLink(env, purpose, id, token) {
  if (typeof id !== 'string' || typeof token !== 'string' || !env.LINK_SECRET) return false;
  const expected = await linkToken(env, purpose, id);
  if (expected.length !== token.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ token.charCodeAt(i);
  return diff === 0;
}

export async function unsubscribeUrl(env, id) {
  return `${env.PUBLIC_BASE_URL}/v1/unsubscribe?u=${encodeURIComponent(id)}&t=${await linkToken(env, 'unsub', id)}`;
}

function mask(email) {
  if (!email) return null;
  const [user, domain] = email.split('@');
  return `${user.slice(0, 1)}***@${domain}`;
}

function maskPhone(p) {
  return p ? `***-***-${p.slice(-4)}` : null;
}

async function readJson(request, max = 4096) {
  const len = Number(request.headers.get('content-length') || 0);
  if (len > max) return null;
  const text = await request.text();
  if (text.length > max) return null;
  try {
    const v = JSON.parse(text);
    return v && typeof v === 'object' && !Array.isArray(v) ? v : null;
  } catch {
    return null;
  }
}

async function readForm(request) {
  const text = (await request.text()).slice(0, 2048);
  return new URLSearchParams(text);
}

function paperLabel(date) {
  return new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })
    .format(new Date(`${date}T12:00:00Z`));
}

function footer(env, app, unsub) {
  const a = APPS[app];
  return {
    text:
      `\n\nYou get this because you turned on email delivery in ${a.name} with an Archive Pass.\n` +
      `Stop these emails: ${unsub}\n${env.POSTAL_ADDRESS}`,
    html:
      `<hr><p style="font-size:12px;color:#666">You get this because you turned on email delivery in ${escapeHtml(a.name)} with an Archive Pass.<br>` +
      `<a href="${escapeHtml(unsub)}">Stop these emails</a><br>${escapeHtml(env.POSTAL_ADDRESS)}</p>`,
  };
}

// ---------------------------------------------------------------- handlers

export async function handleSubscribe(request, env, deps) {
  const { store, now, fetchFn } = deps;
  const body = await readJson(request);
  if (!body) return json({ error: 'bad_request' }, 400);
  const app = body.app;
  if (!APPS[app]) return json({ error: 'bad_app' }, 400);
  const txid = String(body.transactionId ?? '');
  if (!/^\d{1,20}$/.test(txid)) return json({ error: 'bad_transaction' }, 400);

  const ip = request.headers.get('cf-connecting-ip') || 'none';
  if (!(await store.allow(`ip:${await sha256Hex(ip)}`, 20, HOUR, now))) return json({ error: 'slow_down' }, 429);
  if (!(await store.allow(`tx:${app}:${txid}`, 5, HOUR, now))) return json({ error: 'slow_down' }, 429);

  const flags = await remoteFlags(app, fetchFn);
  const email = body.email == null || body.email === '' ? null : normalizeEmail(body.email);
  if (body.email && !email) return json({ error: 'bad_email' }, 400);
  const phone = body.phone == null || body.phone === '' ? null : normalizeUsPhone(body.phone);
  if (body.phone && !phone) return json({ error: 'bad_phone' }, 400);
  if (!email && !phone) return json({ error: 'nothing_to_save' }, 400);
  if (email && !channelAllowed(env, app, flags, 'email')) return json({ error: 'email_off' }, 403);
  if (phone) {
    if (!channelAllowed(env, app, flags, 'sms')) return json({ error: 'sms_off' }, 403);
    if (body.smsConsent !== true || !SMS_CONSENT[body.smsConsentVersion]) return json({ error: 'sms_consent_required' }, 400);
  }
  if (email && (await store.isSuppressed(await sha256Hex(email)))) return json({ error: 'email_blocked' }, 422);
  if (phone && (await store.isSuppressed(await sha256Hex(phone)))) return json({ error: 'phone_opted_out' }, 422);

  let ent;
  try {
    ent = await checkEntitlement(env, app, txid, fetchFn, now);
  } catch {
    return json({ error: 'apple_unavailable' }, 503);
  }
  if (!ent || !ent.active) return json({ error: 'no_active_pass' }, 403);

  const manageToken = randomToken();
  const manageHash = await sha256Hex(manageToken);
  let row = await store.byTransaction(app, ent.originalTransactionId);
  const entFields = {
    product_id: ent.productId,
    entitlement: 'active',
    entitlement_expires_at: ent.expiresAt,
    entitlement_checked_at: now,
    manage_hash: manageHash,
    updated_at: now,
  };
  if (!row) {
    row = { id: crypto.randomUUID(), app, original_transaction_id: ent.originalTransactionId, created_at: now, ...entFields };
    await store.insert(row);
  } else {
    await store.update(row.id, entFields);
  }

  let emailPending = false;
  if (email && (email !== row.email || row.email_unsubscribed_at)) {
    // New address: it waits for its confirm link. The old confirmed
    // address keeps getting the paper until the new one confirms.
    if (!(await store.allow(`confirm:${row.id}`, 3, DAY, now))) return json({ error: 'slow_down' }, 429);
    const token = randomToken();
    await store.update(row.id, { pending_email: email, pending_hash: await sha256Hex(token), pending_expires_at: now + CONFIRM_TTL });
    const link = `${env.PUBLIC_BASE_URL}/v1/confirm?t=${token}`;
    const a = APPS[app];
    const sent = await deps.email.send({
      to: email,
      subject: `Confirm your email for ${a.name}`,
      text: `Tap to start getting ${a.name} by email:\n${link}\n\nThe link works for 48 hours. If you didn't ask for this, ignore this email and nothing happens.\n\n${env.POSTAL_ADDRESS}`,
      html: `<p>Tap to start getting ${escapeHtml(a.name)} by email:</p><p><a href="${escapeHtml(link)}">Confirm my email</a></p><p>The link works for 48 hours. If you didn't ask for this, ignore this email and nothing happens.</p><p style="font-size:12px;color:#666">${escapeHtml(env.POSTAL_ADDRESS)}</p>`,
    });
    if (!sent.ok) return json({ error: 'confirm_send_failed', manageToken }, 502);
    emailPending = true;
  }

  let smsPending = false;
  if (phone && phone !== row.phone) {
    await store.update(row.id, {
      phone,
      sms_consent_at: now,
      sms_consent_text: SMS_CONSENT[body.smsConsentVersion],
      sms_confirmed_at: null,
      sms_opted_out_at: null,
    });
    // The confirmation text ("Reply YES ... STOP to cancel") goes out
    // through the SMS provider once one is wired in. Until then the
    // number waits unconfirmed and gets nothing.
    smsPending = true;
  }
  if (body.removePhone === true && row.phone) {
    await store.update(row.id, { phone: null, sms_consent_at: null, sms_consent_text: null, sms_confirmed_at: null, sms_opted_out_at: null });
  }

  return json({ ok: true, manageToken, emailPending, smsPending });
}

async function rowFromManage(request, store) {
  const body = await readJson(request);
  if (!body || !APPS[body.app] || typeof body.manageToken !== 'string' || body.manageToken.length > 100) return null;
  return store.byManageHash(body.app, await sha256Hex(body.manageToken));
}

export async function handleStatus(request, env, { store }) {
  const row = await rowFromManage(request, store);
  if (!row) return json({ error: 'not_found' }, 404);
  return json({
    ok: true,
    email: mask(row.email_unsubscribed_at ? null : row.email),
    emailPending: mask(row.pending_email),
    phone: maskPhone(row.phone),
    smsConfirmed: !!row.sms_confirmed_at && !row.sms_opted_out_at,
    active: row.entitlement === 'active',
  });
}

export async function handleDelete(request, env, { store }) {
  const row = await rowFromManage(request, store);
  if (!row) return json({ error: 'not_found' }, 404);
  await store.deleteSubscriber(row.id);
  return json({ ok: true });
}

export async function handleConfirm(request, env, { store, now, email: sender }) {
  const url = new URL(request.url);
  if (request.method === 'GET') {
    // A button, not an automatic confirm: mail scanners open links.
    const t = url.searchParams.get('t') || '';
    return html(`<h2>Confirm your email</h2><form method="post" action="/v1/confirm"><input type="hidden" name="t" value="${escapeHtml(t)}"><button type="submit" style="font-size:1.1rem;padding:.6rem 1.2rem">Yes, send me the paper</button></form>`);
  }
  const t = (await readForm(request)).get('t') || '';
  const row = t ? await store.byPendingHash(await sha256Hex(t)) : null;
  if (!row || !row.pending_email || row.pending_expires_at < now) {
    return html('<h2>This link has expired</h2><p>Open the app and enter your email again to get a new link.</p>', 410);
  }
  if (row.entitlement !== 'active') return html('<h2>No active Archive Pass</h2><p>Email delivery comes with the Archive Pass.</p>', 403);
  const old = row.email && !row.email_unsubscribed_at && row.email !== row.pending_email ? row.email : null;
  await store.update(row.id, {
    email: row.pending_email,
    email_confirmed_at: now,
    email_unsubscribed_at: null,
    pending_email: null,
    pending_hash: null,
    pending_expires_at: null,
    updated_at: now,
  });
  if (old) {
    const a = APPS[row.app];
    await sender.send({
      to: old,
      subject: `${a.name} delivery moved`,
      text: `${a.name} will now go to ${mask(row.pending_email)} instead of this address. If you didn't do this, open the app and set your email again.\n\n${env.POSTAL_ADDRESS}`,
      html: `<p>${escapeHtml(a.name)} will now go to ${escapeHtml(mask(row.pending_email))} instead of this address. If you didn't do this, open the app and set your email again.</p><p style="font-size:12px;color:#666">${escapeHtml(env.POSTAL_ADDRESS)}</p>`,
    });
  }
  return html("<h2>You're all set</h2><p>The paper will arrive by email on game days.</p>");
}

export async function handleUnsubscribe(request, env, { store, now }) {
  const url = new URL(request.url);
  let u = url.searchParams.get('u');
  let t = url.searchParams.get('t');
  if (request.method === 'GET') {
    if (!(await verifyLink(env, 'unsub', u, t))) return html('<h2>This link is not valid</h2>', 400);
    const q = `u=${encodeURIComponent(u)}&t=${encodeURIComponent(t)}`;
    return html(
      `<h2>Stop the emails?</h2>` +
        `<form method="post" action="/v1/unsubscribe?${escapeHtml(q)}"><button type="submit">Stop the emails</button></form>` +
        `<p>Or remove everything we hold for you (your email and phone number):</p>` +
        `<form method="post" action="/v1/forget?${escapeHtml(q)}"><button type="submit">Delete my information</button></form>`,
    );
  }
  // POST: one-click (RFC 8058) from the mail app, or the button above.
  if (!(await verifyLink(env, 'unsub', u, t))) return html('<h2>This link is not valid</h2>', 400);
  const row = await store.byId(u);
  if (row) await store.update(row.id, { email_unsubscribed_at: now, updated_at: now });
  return html('<h2>Done</h2><p>No more emails. You can turn delivery back on in the app any time.</p>');
}

export async function handleForget(request, env, { store }) {
  const url = new URL(request.url);
  const u = url.searchParams.get('u');
  if (!(await verifyLink(env, 'unsub', u, url.searchParams.get('t')))) return html('<h2>This link is not valid</h2>', 400);
  const row = await store.byId(u);
  if (row) await store.deleteSubscriber(row.id);
  return html('<h2>Deleted</h2><p>We no longer hold your email or phone number.</p>');
}

export async function handleAppleNotification(request, env, { store, now, fetchFn }) {
  const body = await readJson(request, 64 * 1024);
  const n = notificationTransaction(body);
  if (!n) return json({ ok: true }); // not ours or unreadable: nothing to do
  const row = await store.byTransaction(n.app, n.transactionId);
  if (!row) return json({ ok: true });
  // Never trust the notification itself: ask Apple.
  let ent;
  try {
    ent = await checkEntitlement(env, n.app, n.transactionId, fetchFn, now);
  } catch {
    return json({ error: 'apple_unavailable' }, 500); // Apple retries
  }
  await store.update(row.id, {
    entitlement: ent?.active ? 'active' : 'inactive',
    entitlement_expires_at: ent?.expiresAt ?? null,
    entitlement_checked_at: now,
    updated_at: now,
  });
  return json({ ok: true });
}

/** STOP / HELP / START keywords (carrier rules). Pure, for tests. */
export async function smsKeyword(store, phone, text, now) {
  const word = String(text || '').trim().toUpperCase();
  const rows = await store.byPhone(phone);
  if (['STOP', 'STOPALL', 'UNSUBSCRIBE', 'CANCEL', 'END', 'QUIT', 'REVOKE', 'OPTOUT'].includes(word)) {
    for (const r of rows) await store.update(r.id, { sms_opted_out_at: now, updated_at: now });
    await store.suppress(await sha256Hex(phone), 'sms_stop', now);
    return 'You are unsubscribed and will get no more texts. Reply START to resubscribe.';
  }
  if (['HELP', 'INFO'].includes(word)) {
    return 'Box Score papers by text. Up to 1 msg per game day. Msg and data rates may apply. Reply STOP to cancel. Help: toolstem.com';
  }
  if (['START', 'UNSTOP', 'YES'].includes(word)) {
    return 'Thanks. Turn texts on again in the app to restart delivery.';
  }
  return null;
}

export async function handleSmsInbound(request, env, deps) {
  const sms = smsSender(env);
  if (!(await sms.verifyInbound(request))) return json({ error: 'forbidden' }, 403);
  // Wire-up point once a provider exists: parse From/Body, call
  // smsKeyword, reply with its text.
  return json({ ok: true });
}

// ---------------------------------------------------------------- daily send

/**
 * One cron tick. Sends up to SEND_BATCH emails per app; the next tick
 * continues. Safe to re-run: the deliveries table blocks double sends.
 */
export async function runDaily(env, deps) {
  const { store, now, fetchFn } = deps;
  const report = [];
  const earliest = Number(env.DELIVERY_EARLIEST_HOUR_CT || 7);
  const hourCt = Number(new Intl.DateTimeFormat('en-US', { timeZone: 'America/Chicago', hour: 'numeric', hourCycle: 'h23' }).format(new Date(now)));
  if (hourCt < earliest) return [{ skipped: 'too_early' }];

  // Upkeep: re-ask Apple about a few lapsed rows, delete long-lapsed rows.
  for (const row of await store.staleEntitlements(now, 5)) {
    try {
      const ent = await checkEntitlement(env, row.app, row.original_transaction_id, fetchFn, now);
      await store.update(row.id, {
        entitlement: ent?.active ? 'active' : 'inactive',
        entitlement_expires_at: ent?.expiresAt ?? null,
        entitlement_checked_at: now,
      });
    } catch {
      break; // Apple down: try next tick
    }
  }
  for (const r of await store.expiredForDeletion(now - RETENTION_AFTER_LAPSE, 50)) await store.deleteSubscriber(r.id);
  await store.pruneRateLimits(now - 2 * DAY);

  for (const app of Object.keys(APPS)) {
    report.push(await sendEmailForApp(env, deps, app));
  }
  return report;
}

async function newestPaperDate(app, fetchFn) {
  const bytes = await fetchOwn(APPS[app].editionsUrl, 2 * 1024 * 1024, fetchFn);
  const feed = JSON.parse(new TextDecoder().decode(bytes));
  const dates = (feed.editions ?? []).map((e) => e?.date).filter((d) => typeof d === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(d));
  dates.sort();
  return dates.at(-1) ?? null;
}

export async function sendEmailForApp(env, deps, app) {
  const { store, now, fetchFn } = deps;
  const flags = await remoteFlags(app, fetchFn);
  if (!channelAllowed(env, app, flags, 'email')) return { app, skipped: 'email_off' };
  if (!env.POSTAL_ADDRESS || !env.PUBLIC_BASE_URL || !env.LINK_SECRET) return { app, skipped: 'missing_config' };

  let date;
  try {
    date = await newestPaperDate(app, fetchFn);
  } catch {
    return { app, skipped: 'feed_unreadable' };
  }
  if (!date) return { app, skipped: 'no_paper' };
  const today = chicagoDate(now);
  const maxAge = Number(env.MAX_PAPER_AGE_DAYS || 2);
  if (daysBetween(date, today) > maxAge || daysBetween(date, today) < 0) return { app, skipped: 'no_new_paper', date };

  const existing = await store.getRun(app, date, 'email');
  if (existing?.aborted_reason && env.TRIPWIRE_ACK !== `${app}:${date}`) return { app, skipped: 'tripwire', date, reason: existing.aborted_reason };

  const due = await store.countDueEmail(app, date, now);
  if (due === 0) return { app, date, sent: 0, done: true };

  if (!existing) {
    // Tripwire, checked once at the start of each paper's run.
    const max = Number(env.MAX_RECIPIENTS_PER_RUN || 2000);
    const prev = await store.lastFinishedRun(app, 'email', date);
    await store.startRun(app, date, 'email', now);
    let reason = null;
    if (due > max) reason = `due ${due} > max ${max}`;
    else if (prev && prev.sent > 0 && due > prev.sent * 2 + 50) reason = `due ${due} jumped from ${prev.sent}`;
    if (reason && env.TRIPWIRE_ACK !== `${app}:${date}`) {
      await store.abortRun(app, date, 'email', reason);
      return { app, skipped: 'tripwire', date, reason };
    }
  }

  // The paper itself: our host only, real PDF, attach if small.
  const pdfUrl = APPS[app].pdfUrl(date);
  let pdf;
  try {
    pdf = await fetchOwn(pdfUrl, 5 * 1024 * 1024, fetchFn);
  } catch {
    return { app, skipped: 'pdf_unreadable', date };
  }
  const magic = String.fromCharCode(...pdf.subarray(0, 5));
  if (magic !== '%PDF-') return { app, skipped: 'pdf_not_pdf', date };
  const attach = pdf.length <= 2 * 1024 * 1024;

  const batch = await store.dueEmail(app, date, now, Number(env.SEND_BATCH || 25));
  const a = APPS[app];
  const label = paperLabel(date);
  let sent = 0;
  let failed = 0;
  for (const row of batch) {
    if (await store.isSuppressed(await sha256Hex(row.email))) {
      await store.recordDelivery(row.id, date, 'email', 'suppressed', now);
      continue;
    }
    const unsub = await unsubscribeUrl(env, row.id);
    const f = footer(env, app, unsub);
    const res = await deps.email.send({
      to: row.email,
      subject: `${a.name}, ${label}`,
      text: `Here is the paper for ${label}.\n${attach ? 'The PDF is attached, ready to print.\n' : ''}Open it online: ${pdfUrl}${f.text}`,
      html: `<p>Here is the paper for ${escapeHtml(label)}.</p>${attach ? '<p>The PDF is attached, ready to print.</p>' : ''}<p><a href="${escapeHtml(pdfUrl)}">Open the paper</a></p>${f.html}`,
      unsubscribeUrl: unsub,
      attachment: attach ? { filename: a.fileName(date), bytes: pdf } : undefined,
    });
    // A failure is recorded and not retried: a provider error can still
    // mean the email went out, and a double send is worse than a miss.
    await store.recordDelivery(row.id, date, 'email', res.ok ? 'sent' : 'failed', now);
    if (res.ok) sent++;
    else failed++;
  }
  await store.addToRun(app, date, 'email', sent, failed);
  return { app, date, sent, failed, remaining: Math.max(0, due - batch.length) };
}

// ---------------------------------------------------------------- entry

function deps(env) {
  return { store: makeStore(env.DB), now: Date.now(), fetchFn: fetch, email: emailSender(env) };
}

export async function route(request, env, d) {
  const { pathname } = new URL(request.url);
  const m = request.method;
  if (m === 'POST' && pathname === '/v1/subscribe') return handleSubscribe(request, env, d);
  if (m === 'POST' && pathname === '/v1/status') return handleStatus(request, env, d);
  if (m === 'POST' && pathname === '/v1/delete') return handleDelete(request, env, d);
  if ((m === 'GET' || m === 'POST') && pathname === '/v1/confirm') return handleConfirm(request, env, d);
  if ((m === 'GET' || m === 'POST') && pathname === '/v1/unsubscribe') return handleUnsubscribe(request, env, d);
  if (m === 'POST' && pathname === '/v1/forget') return handleForget(request, env, d);
  if (m === 'POST' && pathname === '/v1/apple/notifications') return handleAppleNotification(request, env, d);
  if (m === 'POST' && pathname === '/v1/sms/inbound') return handleSmsInbound(request, env, d);
  return json({ error: 'not_found' }, 404);
}

export default {
  async fetch(request, env) {
    try {
      return await route(request, env, deps(env));
    } catch {
      return json({ error: 'server_error' }, 500);
    }
  },
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(runDaily(env, deps(env)));
  },
};
