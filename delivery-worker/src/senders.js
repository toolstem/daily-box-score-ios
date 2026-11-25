// Sender abstraction. Pick one with EMAIL_PROVIDER = "ses" | "resend" | "log".
// "log" (the default) sends nothing: it only counts, for dry runs.
// Text messages: only a stub until a provider is chosen and the
// A2P 10DLC registration is approved. No provider account exists.

const te = new TextEncoder();

function b64(bytes) {
  let s = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) s += String.fromCharCode(...bytes.subarray(i, i + chunk));
  return btoa(s);
}

/** message: { to, subject, text, html, unsubscribeUrl, attachment?: {filename, bytes} } */
export function emailSender(env, fetchFn = fetch) {
  const provider = env.EMAIL_PROVIDER || 'log';
  if (provider === 'resend') return resendSender(env, fetchFn);
  if (provider === 'ses') return sesSender(env, fetchFn);
  return logSender();
}

export function logSender() {
  const sent = [];
  return {
    name: 'log',
    sent,
    async send(msg) {
      sent.push({ to: msg.to, subject: msg.subject });
      return { ok: true };
    },
  };
}

function listHeaders(msg) {
  return {
    'List-Unsubscribe': `<${msg.unsubscribeUrl}>`,
    'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
  };
}

export function resendSender(env, fetchFn) {
  return {
    name: 'resend',
    async send(msg) {
      const body = {
        from: env.EMAIL_FROM,
        to: [msg.to],
        subject: msg.subject,
        text: msg.text,
        html: msg.html,
        headers: msg.unsubscribeUrl ? listHeaders(msg) : undefined,
        attachments: msg.attachment ? [{ filename: msg.attachment.filename, content: b64(msg.attachment.bytes) }] : undefined,
      };
      const res = await fetchFn('https://api.resend.com/emails', {
        method: 'POST',
        headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, 'content-type': 'application/json' },
        body: JSON.stringify(body),
      });
      return { ok: res.ok, status: res.status };
    },
  };
}

// ---------- Amazon SES v2 (raw MIME, so the PDF and List-Unsubscribe fit) ----------

export function buildMime(from, msg, boundarySeed = crypto.randomUUID()) {
  const b1 = `mix-${boundarySeed}`;
  const b2 = `alt-${boundarySeed}`;
  const lines = [
    `From: ${from}`,
    `To: ${msg.to}`,
    `Subject: ${msg.subject}`,
    'MIME-Version: 1.0',
  ];
  if (msg.unsubscribeUrl) {
    const h = listHeaders(msg);
    lines.push(`List-Unsubscribe: ${h['List-Unsubscribe']}`, `List-Unsubscribe-Post: ${h['List-Unsubscribe-Post']}`);
  }
  lines.push(`Content-Type: multipart/mixed; boundary="${b1}"`, '', `--${b1}`,
    `Content-Type: multipart/alternative; boundary="${b2}"`, '',
    `--${b2}`, 'Content-Type: text/plain; charset=UTF-8', 'Content-Transfer-Encoding: base64', '', wrap(b64(te.encode(msg.text))),
    `--${b2}`, 'Content-Type: text/html; charset=UTF-8', 'Content-Transfer-Encoding: base64', '', wrap(b64(te.encode(msg.html))),
    `--${b2}--`);
  if (msg.attachment) {
    lines.push(`--${b1}`, `Content-Type: application/pdf; name="${msg.attachment.filename}"`,
      'Content-Transfer-Encoding: base64', `Content-Disposition: attachment; filename="${msg.attachment.filename}"`, '',
      wrap(b64(msg.attachment.bytes)));
  }
  lines.push(`--${b1}--`, '');
  return lines.join('\r\n');
}

function wrap(s) {
  return s.replace(/(.{76})/g, '$1\r\n');
}

async function hmac(key, data) {
  const k = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', k, te.encode(data)));
}

async function sha256HexBytes(data) {
  const buf = await crypto.subtle.digest('SHA-256', typeof data === 'string' ? te.encode(data) : data);
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

const hex = (u8) => [...u8].map((b) => b.toString(16).padStart(2, '0')).join('');

/** AWS Signature Version 4 headers for one JSON POST. */
export async function sigV4(env, host, path, body, now = new Date()) {
  const region = env.AWS_REGION;
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, '');
  const day = amzDate.slice(0, 8);
  const payloadHash = await sha256HexBytes(body);
  const canonical = ['POST', path, '', `content-type:application/json\nhost:${host}\nx-amz-date:${amzDate}\n`, 'content-type;host;x-amz-date', payloadHash].join('\n');
  const scope = `${day}/${region}/ses/aws4_request`;
  const toSign = ['AWS4-HMAC-SHA256', amzDate, scope, await sha256HexBytes(canonical)].join('\n');
  let k = await hmac(te.encode(`AWS4${env.AWS_SECRET_ACCESS_KEY}`), day);
  k = await hmac(k, region);
  k = await hmac(k, 'ses');
  k = await hmac(k, 'aws4_request');
  const signature = hex(await hmac(k, toSign));
  return {
    'content-type': 'application/json',
    'x-amz-date': amzDate,
    authorization: `AWS4-HMAC-SHA256 Credential=${env.AWS_ACCESS_KEY_ID}/${scope}, SignedHeaders=content-type;host;x-amz-date, Signature=${signature}`,
  };
}

export function sesSender(env, fetchFn) {
  return {
    name: 'ses',
    async send(msg) {
      const host = `email.${env.AWS_REGION}.amazonaws.com`;
      const path = '/v2/email/outbound-emails';
      const raw = buildMime(env.EMAIL_FROM, msg);
      const body = JSON.stringify({
        FromEmailAddress: env.EMAIL_FROM,
        Destination: { ToAddresses: [msg.to] },
        Content: { Raw: { Data: b64(te.encode(raw)) } },
        ...(env.SES_CONFIGURATION_SET ? { ConfigurationSetName: env.SES_CONFIGURATION_SET } : {}),
      });
      const headers = await sigV4(env, host, path, body);
      const res = await fetchFn(`https://${host}${path}`, { method: 'POST', headers, body });
      return { ok: res.ok, status: res.status };
    },
  };
}

// ---------- Text messages: stub only ----------

/** Always refuses until a provider is wired in. sms_enabled stays false. */
export function smsSender(env) {
  return {
    name: env.SMS_PROVIDER || 'none',
    async send() {
      return { ok: false, status: 0, error: 'sms_provider_not_configured' };
    },
    /** Inbound webhook signature check; refuses everything until wired. */
    async verifyInbound() {
      return false;
    },
  };
}
