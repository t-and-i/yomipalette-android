import { PACKAGE_NAME } from './play-api.js';
import { validDeviceId, OFFLINE_GRANT_SECONDS } from './offline-grants.js';
import { tokenHash } from './revocations.js';
import { allowVerifyToken } from './rate-limits.js';

const encode = bytes => btoa(String.fromCharCode(...bytes))
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
const credentialPattern = /^[A-Za-z0-9_-]{43}$/;

function json(status, value) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store, private' },
  });
}

export async function issueReviewGrant(env, deviceId, nowMs) {
  if (!validDeviceId(deviceId) || !/^[A-Za-z0-9_-]{1,32}$/.test(env.OFFLINE_GRANT_KEY_ID || '') ||
      !env.OFFLINE_GRANT_PRIVATE_KEY_PKCS8) throw new Error('Review signing unavailable');
  const iat = Math.floor(nowMs / 1000);
  const payload = new TextEncoder().encode(JSON.stringify({
    v: 3, kind: 'review', kid: env.OFFLINE_GRANT_KEY_ID,
    pkg: PACKAGE_NAME, deviceId, iat, exp: iat + OFFLINE_GRANT_SECONDS,
  }));
  const key = await crypto.subtle.importKey('pkcs8',
    Uint8Array.from(atob(env.OFFLINE_GRANT_PRIVATE_KEY_PKCS8), c => c.charCodeAt(0)),
    { name: 'Ed25519' }, false, ['sign']);
  const signature = await crypto.subtle.sign('Ed25519', key, payload);
  return encode(payload) + '.' + encode(new Uint8Array(signature));
}

// This explicit credential flow does not require Google identity or a Play
// licensing verdict. Purchase and trial endpoints retain their Integrity policy.
export async function handleReview(body, env, { now = Date.now } = {}) {
  if (!body || body.packageName !== PACKAGE_NAME || !validDeviceId(body.deviceId) ||
      !['register', 'refresh'].includes(body.action)) {
    return json(400, { status: 'invalid' });
  }
  if (body.action === 'register') {
    if (typeof env.REVIEW_ACCESS_TOKEN !== 'string' || env.REVIEW_ACCESS_TOKEN.length < 32 ||
        env.REVIEW_ACCESS_TOKEN.length > 512) {
      return json(503, { status: 'unavailable' });
    }
    if (typeof body.token !== 'string' || body.token.length > 512) {
      return json(401, { status: 'rejected' });
    }
    // Hash before comparing so comparisons always process a fixed-length value.
    const supplied = await tokenHash(body.token);
    const tokens = [env.REVIEW_ACCESS_TOKEN];
    if (typeof env.REVIEW_ACCESS_TOKEN_PREVIOUS === 'string' &&
        env.REVIEW_ACCESS_TOKEN_PREVIOUS.length >= 32 &&
        env.REVIEW_ACCESS_TOKEN_PREVIOUS.length <= 512) tokens.push(env.REVIEW_ACCESS_TOKEN_PREVIOUS);
    let matched = 0;
    for (const token of tokens) {
      const expected = await tokenHash(token);
      let difference = 0;
      for (let i = 0; i < expected.length; i++) difference |= supplied.charCodeAt(i) ^ expected.charCodeAt(i);
      matched |= Number(difference === 0);
    }
    if (!matched) return json(401, { status: 'rejected' });
    const credential = encode(crypto.getRandomValues(new Uint8Array(32)));
    const hash = await tokenHash(credential);
    // Sign first. Signing failure must not create an unusable registration.
    const grant = await issueReviewGrant(env, body.deviceId, now());
    await env.ENTITLEMENTS_DB.prepare(
      'INSERT INTO review_installations (credential_hash, device_id, created_at_ms) VALUES (?, ?, ?)'
    ).bind(hash, body.deviceId, now()).run();
    return json(200, { status: 'active', credential, grant });
  }
  if (typeof body.credential !== 'string' || !credentialPattern.test(body.credential)) {
    return json(401, { status: 'rejected' });
  }
  const hash = await tokenHash(body.credential);
  if (!await allowVerifyToken(env, hash)) return json(429, { status: 'unavailable' });
  const row = await env.ENTITLEMENTS_DB.prepare(
    'SELECT device_id, revoked_at_ms FROM review_installations WHERE credential_hash = ?'
  ).bind(hash).first();
  if (!row || row.device_id !== body.deviceId || row.revoked_at_ms !== null) {
    return json(401, { status: 'rejected' });
  }
  return json(200, { status: 'active', grant: await issueReviewGrant(env, body.deviceId, now()) });
}
