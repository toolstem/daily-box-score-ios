// App Store Server API: the source of truth for whether someone
// holds the pass. The app sends only a transaction ID; we ask Apple
// directly over TLS and trust only Apple's answer. Notifications V2
// are treated as a nudge to re-ask Apple, never trusted on their own.

import { base64url, base64urlDecodeToString } from './util.js';
import { APPS } from './apps.js';

const PROD = 'https://api.storekit.itunes.apple.com';
const SANDBOX = 'https://api.storekit-sandbox.itunes.apple.com';

let cachedKey = null;

async function importKey(pem) {
  if (cachedKey && cachedKey.pem === pem) return cachedKey.key;
  const body = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  cachedKey = { pem, key };
  return key;
}

/** ES256 JWT for the App Store Server API (In-App Purchase key). */
export async function appleJwt(env, bundleId, nowMs = Date.now()) {
  const header = { alg: 'ES256', kid: env.APPLE_KEY_ID, typ: 'JWT' };
  const iat = Math.floor(nowMs / 1000);
  const payload = { iss: env.APPLE_ISSUER_ID, iat, exp: iat + 600, aud: 'appstoreconnect-v1', bid: bundleId };
  const te = new TextEncoder();
  const signingInput = `${base64url(te.encode(JSON.stringify(header)))}.${base64url(te.encode(JSON.stringify(payload)))}`;
  const key = await importKey(env.APPLE_PRIVATE_KEY);
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, te.encode(signingInput));
  return `${signingInput}.${base64url(new Uint8Array(sig))}`;
}

/** Payload of a JWS we received from Apple over TLS (not re-verified). */
export function jwsPayload(jws) {
  if (typeof jws !== 'string') return null;
  const parts = jws.split('.');
  if (parts.length !== 3) return null;
  try {
    return JSON.parse(base64urlDecodeToString(parts[1]));
  } catch {
    return null;
  }
}

async function appleGet(env, app, path, fetchFn) {
  const bases = env.APPLE_ALLOW_SANDBOX === 'true' ? [PROD, SANDBOX] : [PROD];
  for (const base of bases) {
    const token = await appleJwt(env, APPS[app].bundleId);
    const res = await fetchFn(`${base}${path}`, { headers: { authorization: `Bearer ${token}` } });
    if (res.status === 200) return res.json();
    if (res.status === 404 || res.status === 400) continue; // try sandbox if allowed
    throw new Error(`apple_${res.status}`);
  }
  return null;
}

/**
 * Asks Apple about one transaction and returns the entitlement:
 * { originalTransactionId, productId, active, expiresAt } or null when
 * Apple does not know it, it belongs to another app, or it is not a
 * pass product (tips never count).
 */
export async function checkEntitlement(env, app, transactionId, fetchFn = fetch, nowMs = Date.now()) {
  if (!APPS[app] || !/^\d{1,20}$/.test(String(transactionId))) return null;
  const info = await appleGet(env, app, `/inApps/v1/transactions/${transactionId}`, fetchFn);
  const tx = info && jwsPayload(info.signedTransactionInfo);
  if (!tx) return null;
  if (tx.bundleId !== APPS[app].bundleId) return null;
  if (!APPS[app].passProductIds.includes(tx.productId)) return null;

  const original = String(tx.originalTransactionId);
  if (tx.type === 'Non-Consumable') {
    return { originalTransactionId: original, productId: tx.productId, active: !tx.revocationDate, expiresAt: null };
  }

  // Subscription: ask for the current status of the whole chain, so
  // renewals, expiry, billing failure and refunds are all reflected.
  const status = await appleGet(env, app, `/inApps/v1/subscriptions/${original}`, fetchFn);
  let best = null;
  for (const group of status?.data ?? []) {
    for (const last of group.lastTransactions ?? []) {
      if (String(last.originalTransactionId) !== original) continue;
      const t = jwsPayload(last.signedTransactionInfo) ?? {};
      // 1 active, 4 billing grace period: still entitled.
      // 2 expired, 3 billing retry, 5 revoked: not entitled.
      const active = (last.status === 1 || last.status === 4) && !t.revocationDate;
      best = { originalTransactionId: original, productId: t.productId ?? tx.productId, active, expiresAt: t.expiresDate ?? null };
    }
  }
  if (!best) {
    best = {
      originalTransactionId: original,
      productId: tx.productId,
      active: !tx.revocationDate && typeof tx.expiresDate === 'number' && tx.expiresDate > nowMs,
      expiresAt: tx.expiresDate ?? null,
    };
  }
  return best;
}

/**
 * Pulls the transaction ID out of an App Store Server Notification V2.
 * The payload is NOT trusted: the caller re-checks with Apple.
 */
export function notificationTransaction(body) {
  const outer = jwsPayload(body?.signedPayload);
  if (!outer?.data) return null;
  const app = Object.keys(APPS).find((k) => APPS[k].bundleId === outer.data.bundleId);
  const tx = jwsPayload(outer.data.signedTransactionInfo);
  if (!app || !tx?.originalTransactionId) return null;
  return { app, transactionId: String(tx.originalTransactionId), type: outer.notificationType };
}
