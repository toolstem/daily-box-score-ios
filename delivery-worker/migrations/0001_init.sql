-- Box score paper delivery: one row per pass purchase per app.
-- Only what delivery needs: an email and/or a phone number, tied to
-- Apple's original transaction ID. No names, no device IDs, no
-- analytics. Confirm and manage tokens are stored as SHA-256 hashes
-- only. Unsubscribe links are signed (HMAC with LINK_SECRET), so
-- nothing about them is stored.

CREATE TABLE IF NOT EXISTS subscribers (
  id TEXT PRIMARY KEY,                       -- random UUID
  app TEXT NOT NULL CHECK (app IN ('baseball', 'football')),
  original_transaction_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  entitlement TEXT NOT NULL CHECK (entitlement IN ('active', 'inactive')),
  entitlement_expires_at INTEGER,            -- ms; NULL for lifetime
  entitlement_checked_at INTEGER NOT NULL,

  email TEXT,                                -- confirmed address papers go to
  email_confirmed_at INTEGER,
  email_unsubscribed_at INTEGER,
  pending_email TEXT,                        -- new address waiting for its confirm link
  pending_hash TEXT,
  pending_expires_at INTEGER,

  phone TEXT,                                -- E.164, US only for now
  sms_consent_at INTEGER,
  sms_consent_text TEXT,                     -- exact words the person agreed to
  sms_confirmed_at INTEGER,
  sms_opted_out_at INTEGER,

  pending_manage_hash TEXT,                  -- new phone: token starts working once the new email is confirmed
  manage_hash TEXT NOT NULL,                 -- held by the app, for status and delete
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE (app, original_transaction_id)
);

CREATE INDEX IF NOT EXISTS idx_sub_pending ON subscribers (pending_hash);
CREATE INDEX IF NOT EXISTS idx_sub_manage ON subscribers (manage_hash);
CREATE INDEX IF NOT EXISTS idx_sub_phone ON subscribers (phone);

-- One row per paper per channel per person: makes the daily send
-- safe to re-run (never a double send).
CREATE TABLE IF NOT EXISTS deliveries (
  subscriber_id TEXT NOT NULL,
  paper_date TEXT NOT NULL,                  -- YYYY-MM-DD
  channel TEXT NOT NULL CHECK (channel IN ('email', 'sms')),
  status TEXT NOT NULL,                      -- sending | sent | failed | suppressed
  sent_at INTEGER NOT NULL,
  PRIMARY KEY (subscriber_id, paper_date, channel)
);

-- Addresses that bounced, complained, or asked to be deleted: kept
-- only as a SHA-256 hash so they are never mailed again by mistake.
CREATE TABLE IF NOT EXISTS suppressions (
  address_hash TEXT PRIMARY KEY,
  reason TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

-- One row per daily run, for the tripwire and the audit trail.
CREATE TABLE IF NOT EXISTS send_runs (
  app TEXT NOT NULL,
  paper_date TEXT NOT NULL,
  channel TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  sent INTEGER NOT NULL DEFAULT 0,
  failed INTEGER NOT NULL DEFAULT 0,
  aborted_reason TEXT,
  PRIMARY KEY (app, paper_date, channel)
);

-- Fixed-window rate limits for the public endpoints (hashed key).
CREATE TABLE IF NOT EXISTS rate_limits (
  bucket TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  count INTEGER NOT NULL
);
