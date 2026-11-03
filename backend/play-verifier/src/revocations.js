import { listVoidedPurchases } from './play-api.js';

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const LOOKBACK = 29 * DAY;
export const FRESHNESS_LIMIT_MS = 12 * HOUR;

export async function tokenHash(token) {
  const buffer = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(token),
  );
  return Array.from(new Uint8Array(buffer))
    .map((value) => value.toString(16).padStart(2, '0'))
    .join('');
}

export async function checkRevocation(db, hash, currentMs = Date.now()) {
  if (!db) throw new Error('D1 database binding is missing.');
  const sync = await db.prepare(
    'SELECT completed_at_ms FROM sync_state WHERE key = ?',
  ).bind('voided_purchases').first();

  if (
    !sync ||
    !Number.isFinite(Number(sync.completed_at_ms)) ||
    currentMs - Number(sync.completed_at_ms) > FRESHNESS_LIMIT_MS ||
    Number(sync.completed_at_ms) > currentMs + 300000
  ) {
    throw new Error('Voided purchase sync is stale or not initialized.');
  }

  const revoked = await db.prepare(
    'SELECT token_hash FROM revoked_purchase_tokens WHERE token_hash = ?',
  ).bind(hash).first();
  return revoked != null;
}

export async function syncVoidedPurchases(db, accessToken, {
  now = Date.now,
  fetchImpl = fetch,
} = {}) {
  if (!db) throw new Error('D1 database binding is missing.');
  const currentMs = now();
  const state = await db.prepare(
    'SELECT completed_at_ms FROM sync_state WHERE key = ?',
  ).bind('voided_purchases').first();
  const previous = state?.completed_at_ms == null
    ? null
    : Number(state.completed_at_ms);
  if (
    previous != null &&
    (!Number.isFinite(previous) || currentMs - previous > LOOKBACK)
  ) {
    throw new Error(
      'Sync gap exceeds the Google Play voided purchase lookback; manual reconciliation required.',
    );
  }

  // Begin 29 days back on first run; otherwise overlap two days to
  // account for reporting delays in Google Play's voided-purchase feed.
  const startTime = previous == null
    ? currentMs - LOOKBACK
    : Math.max(currentMs - LOOKBACK, previous - 2 * DAY);
  let pageToken = null;
  let count = 0;
  for (let page = 0; page < 100; page++) {
    const result = await listVoidedPurchases(accessToken, {
      startTime,
      endTime: currentMs,
      pageToken,
      fetchImpl,
    });
    for (const item of result.voided) {
      if (typeof item?.purchaseToken !== 'string') continue;
      const hash = await tokenHash(item.purchaseToken);
      const voidedTime = Number(item.voidedTimeMillis ?? currentMs);
      await db.prepare(
        'INSERT INTO revoked_purchase_tokens (token_hash, voided_at_ms) VALUES (?, ?) ' +
        'ON CONFLICT(token_hash) DO UPDATE SET voided_at_ms = MAX(voided_at_ms, excluded.voided_at_ms)',
      ).bind(hash, Number.isFinite(voidedTime) ? voidedTime : currentMs).run();
      count++;
    }
    pageToken = result.nextPageToken;
    if (!pageToken) {
      // Update freshness only after ALL pages are stored.
      await db.prepare(
        'INSERT INTO sync_state (key, completed_at_ms) VALUES (?, ?) ' +
        'ON CONFLICT(key) DO UPDATE SET completed_at_ms = excluded.completed_at_ms',
      ).bind('voided_purchases', currentMs).run();
      return count;
    }
  }
  throw new Error('Voided purchases pagination limit reached.');
}
