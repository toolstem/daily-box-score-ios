// Database access (Cloudflare D1). Every query is a prepared
// statement with bound values: no string-built SQL.

export function makeStore(db) {
  const one = (sql, ...args) => db.prepare(sql).bind(...args).first();
  const all = async (sql, ...args) => (await db.prepare(sql).bind(...args).all()).results ?? [];
  const run = (sql, ...args) => db.prepare(sql).bind(...args).run();

  return {
    byTransaction: (app, otid) =>
      one('SELECT * FROM subscribers WHERE app = ? AND original_transaction_id = ?', app, otid),
    byPendingHash: (h) => one('SELECT * FROM subscribers WHERE pending_hash = ?', h),
    byId: (id) => one('SELECT * FROM subscribers WHERE id = ?', id),
    byManageHash: (app, h) => one('SELECT * FROM subscribers WHERE app = ? AND manage_hash = ?', app, h),
    byPhone: (phone) => all('SELECT * FROM subscribers WHERE phone = ?', phone),

    async insert(row) {
      const cols = Object.keys(row);
      await run(
        `INSERT INTO subscribers (${cols.join(', ')}) VALUES (${cols.map(() => '?').join(', ')})`,
        ...cols.map((c) => row[c]),
      );
    },

    async update(id, fields) {
      const cols = Object.keys(fields);
      if (!cols.length) return;
      for (const c of cols) if (!/^[a-z_]+$/.test(c)) throw new Error('bad column');
      await run(`UPDATE subscribers SET ${cols.map((c) => `${c} = ?`).join(', ')} WHERE id = ?`, ...cols.map((c) => fields[c]), id);
    },

    deleteSubscriber: async (id) => {
      await run('DELETE FROM deliveries WHERE subscriber_id = ?', id);
      await run('DELETE FROM subscribers WHERE id = ?', id);
    },

    isSuppressed: async (hash) => !!(await one('SELECT 1 AS x FROM suppressions WHERE address_hash = ?', hash)),
    suppress: (hash, reason, now) =>
      run('INSERT OR IGNORE INTO suppressions (address_hash, reason, created_at) VALUES (?, ?, ?)', hash, reason, now),

    /** People due today's email: active pass, confirmed, not unsubscribed, not yet sent. */
    dueEmail: (app, date, now, limit) =>
      all(
        `SELECT s.* FROM subscribers s
         WHERE s.app = ? AND s.entitlement = 'active'
           AND (s.entitlement_expires_at IS NULL OR s.entitlement_expires_at > ?)
           AND s.email IS NOT NULL AND s.email_confirmed_at IS NOT NULL AND s.email_unsubscribed_at IS NULL
           AND NOT EXISTS (SELECT 1 FROM deliveries d WHERE d.subscriber_id = s.id AND d.paper_date = ? AND d.channel = 'email')
         ORDER BY s.created_at LIMIT ?`,
        app, now, date, limit,
      ),
    countDueEmail: async (app, date, now) =>
      (await one(
        `SELECT COUNT(*) AS n FROM subscribers s
         WHERE s.app = ? AND s.entitlement = 'active'
           AND (s.entitlement_expires_at IS NULL OR s.entitlement_expires_at > ?)
           AND s.email IS NOT NULL AND s.email_confirmed_at IS NOT NULL AND s.email_unsubscribed_at IS NULL
           AND NOT EXISTS (SELECT 1 FROM deliveries d WHERE d.subscriber_id = s.id AND d.paper_date = ? AND d.channel = 'email')`,
        app, now, date,
      ))?.n ?? 0,

    /** Active rows whose subscription date has passed: re-ask Apple (missed notification). */
    staleEntitlements: (now, limit) =>
      all(
        `SELECT * FROM subscribers WHERE entitlement = 'active'
           AND entitlement_expires_at IS NOT NULL AND entitlement_expires_at <= ?
         ORDER BY entitlement_checked_at LIMIT ?`,
        now, limit,
      ),
    /** Rows that lost the pass more than retentionMs ago: deleted outright. */
    expiredForDeletion: (cutoff, limit) =>
      all(`SELECT id FROM subscribers WHERE entitlement = 'inactive' AND entitlement_checked_at < ? LIMIT ?`, cutoff, limit),

    recordDelivery: (sid, date, channel, status, now) =>
      run(
        'INSERT OR IGNORE INTO deliveries (subscriber_id, paper_date, channel, status, sent_at) VALUES (?, ?, ?, ?, ?)',
        sid, date, channel, status, now,
      ),
    /** Reserves one send. False if this person already has a row for this paper. */
    async claimDelivery(sid, date, channel, now) {
      const r = await run(
        "INSERT OR IGNORE INTO deliveries (subscriber_id, paper_date, channel, status, sent_at) VALUES (?, ?, ?, 'sending', ?)",
        sid, date, channel, now,
      );
      return (r?.meta?.changes ?? r?.changes ?? 0) > 0;
    },
    finishDelivery: (sid, date, channel, status) =>
      run('UPDATE deliveries SET status = ? WHERE subscriber_id = ? AND paper_date = ? AND channel = ?', status, sid, date, channel),
    unsuppress: (hash) => run('DELETE FROM suppressions WHERE address_hash = ?', hash),
    clearExpiredPending: (now) =>
      run(
        'UPDATE subscribers SET pending_email = NULL, pending_hash = NULL, pending_expires_at = NULL, pending_manage_hash = NULL WHERE pending_expires_at IS NOT NULL AND pending_expires_at < ?',
        now,
      ),

    getRun: (app, date, channel) => one('SELECT * FROM send_runs WHERE app = ? AND paper_date = ? AND channel = ?', app, date, channel),
    lastFinishedRun: (app, channel, date) =>
      one('SELECT * FROM send_runs WHERE app = ? AND channel = ? AND paper_date < ? ORDER BY paper_date DESC LIMIT 1', app, channel, date),
    startRun: (app, date, channel, now) =>
      run('INSERT OR IGNORE INTO send_runs (app, paper_date, channel, started_at) VALUES (?, ?, ?, ?)', app, date, channel, now),
    addToRun: (app, date, channel, sent, failed) =>
      run('UPDATE send_runs SET sent = sent + ?, failed = failed + ? WHERE app = ? AND paper_date = ? AND channel = ?', sent, failed, app, date, channel),
    abortRun: (app, date, channel, reason) =>
      run('UPDATE send_runs SET aborted_reason = ? WHERE app = ? AND paper_date = ? AND channel = ?', reason, app, date, channel),

    /** Fixed-window counter. Returns true while under the limit. */
    async allow(bucket, limit, windowMs, now) {
      const row = await one('SELECT window_start, count FROM rate_limits WHERE bucket = ?', bucket);
      if (!row || now - row.window_start >= windowMs) {
        await run('INSERT OR REPLACE INTO rate_limits (bucket, window_start, count) VALUES (?, ?, 1)', bucket, now);
        return true;
      }
      if (row.count >= limit) return false;
      await run('UPDATE rate_limits SET count = count + 1 WHERE bucket = ?', bucket);
      return true;
    },
    pruneRateLimits: (cutoff) => run('DELETE FROM rate_limits WHERE window_start < ?', cutoff),
  };
}
