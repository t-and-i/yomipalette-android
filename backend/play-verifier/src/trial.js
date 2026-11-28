import { PACKAGE_NAME } from './play-api.js';
import { validDeviceId } from './offline-grants.js';
import { tokenHash } from './revocations.js';
import { verifyGoogleIdToken } from './google-id-token.js';
import { issueTrialGrant, TRIAL_SECONDS } from './trial-grants.js';
import { allowVerifyToken } from './rate-limits.js';
import { verifyIntegrityHash, INTEGRITY_SCOPE } from './play-integrity.js';
import { getPlayAccessToken } from './oauth.js';

function json(status, body) {
  return Response.json(body, {
    status,
    headers: { 'Cache-Control': 'no-store, private',
      'X-Content-Type-Options': 'nosniff' },
  });
}

export function validTrialPayload(body) {
  return body?.packageName === PACKAGE_NAME &&
    validDeviceId(body.deviceId) &&
    typeof body.googleIdToken === 'string' &&
    body.googleIdToken.length >= 80 && body.googleIdToken.length <= 8192 &&
    typeof body.integrityToken === 'string' &&
    body.integrityToken.length >= 1 && body.integrityToken.length <= 16384 &&
    typeof body.requestId === 'string' && /^[a-f0-9]{32}$/.test(body.requestId);
}

export async function subjectDigest(sub, keyBase64Url) {
  if (typeof keyBase64Url !== 'string' || !/^[a-zA-Z0-9_-]{43}$/.test(keyBase64Url)) {
    throw new Error('Trial HMAC secret missing');
  }
  const decoded = atob(keyBase64Url.replace(/-/g, '+').replace(/_/g, '/')
    .padEnd(44, '='));
  const key = await crypto.subtle.importKey('raw',
    Uint8Array.from(decoded, c => c.charCodeAt(0)), { name: 'HMAC', hash: 'SHA-256' },
    false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key,
    new TextEncoder().encode('yomipalette:trial:v1:' + sub)));
  return Array.from(sig, x => x.toString(16).padStart(2, '0')).join('');
}

/** Never refresh started_at / expires_at for an existing subject. */
export async function getOrStartTrial(db, subjectKey, nowMs) {
  if (!db || !/^[a-f0-9]{64}$/.test(subjectKey)) throw new Error('Invalid trial state');
  const end = nowMs + TRIAL_SECONDS * 1000;
  await db.prepare(
    'INSERT OR IGNORE INTO trial_entitlements ' +
    '(subject_key, started_at_ms, expires_at_ms, last_verified_at_ms, status) ' +
    "VALUES (?, ?, ?, ?, 'active')"
  ).bind(subjectKey, nowMs, end, nowMs).run();
  const row = await db.prepare(
    'SELECT started_at_ms, expires_at_ms, status FROM trial_entitlements WHERE subject_key = ?'
  ).bind(subjectKey).first();
  if (!row || !Number.isSafeInteger(Number(row.started_at_ms)) ||
      !Number.isSafeInteger(Number(row.expires_at_ms)) ||
      Number(row.expires_at_ms) - Number(row.started_at_ms) !== TRIAL_SECONDS * 1000 ||
      !['active', 'blocked'].includes(row.status)) throw new Error('Invalid trial record');
  await db.prepare(
    'UPDATE trial_entitlements SET last_verified_at_ms = ? WHERE subject_key = ?'
  ).bind(nowMs, subjectKey).run();
  return { startedAtMs: Number(row.started_at_ms),
    expiresAtMs: Number(row.expires_at_ms), status: row.status };
}

export async function handleTrial(payload, env, {
  now = Date.now, fetchImpl = fetch,
  getAccessToken = getPlayAccessToken,
  verifyIdentity = verifyGoogleIdToken,
} = {}) {
  if (!validTrialPayload(payload)) return json(400, { status: 'invalid_request' });
  if (!env.GOOGLE_SIGN_IN_WEB_CLIENT_ID || !env.TRIAL_SUBJECT_HMAC_KEY ||
      !env.OFFLINE_GRANT_KEY_ID || !env.OFFLINE_GRANT_PRIVATE_KEY_PKCS8 ||
      !env.ENTITLEMENTS_DB) return json(503, { status: 'unavailable' });
  try {
    const sub = await verifyIdentity(payload.googleIdToken,
      env.GOOGLE_SIGN_IN_WEB_CLIENT_ID, { now, fetchImpl });
    if (!sub) return json(401, { status: 'unauthorized' });
    const subjectKey = await subjectDigest(sub, env.TRIAL_SUBJECT_HMAC_KEY);
    if (!await allowVerifyToken(env, subjectKey)) return json(429, { status: 'unavailable' });
    const idTokenHash = await tokenHash(payload.googleIdToken);
    const expectedHash = await tokenHash(JSON.stringify([
      'yomipalette:/trial:v1', PACKAGE_NAME, idTokenHash,
      payload.requestId, payload.deviceId,
    ]));
    const accessToken = await getAccessToken(env, {
      scope: INTEGRITY_SCOPE, fetchImpl, now,
    });
    if (!await verifyIntegrityHash(payload, expectedHash, accessToken,
      { fetchImpl, now })) return json(503, { status: 'unavailable' });
    const timestamp = now();
    const record = await getOrStartTrial(env.ENTITLEMENTS_DB, subjectKey, timestamp);
    if (record.status === 'blocked') return json(200, { status: 'blocked' });
    if (timestamp >= record.expiresAtMs) {
      return json(200, { status: 'expired' });
    }
    const offlineGrant = await issueTrialGrant(env, {
      deviceId: payload.deviceId,
      startedAtMs: record.startedAtMs,
      expiresAtMs: record.expiresAtMs,
    }, timestamp);
    if (!offlineGrant) return json(200, { status: 'expired' });
    return json(200, { status: 'active', offlineGrant });
  } catch {
    return json(503, { status: 'unavailable' });
  }
}
