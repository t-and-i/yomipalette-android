import { PACKAGE_NAME } from './play-api.js';
import { OFFLINE_GRANT_SECONDS, validDeviceId } from './offline-grants.js';

export const TRIAL_SECONDS = 30 * 24 * 3600;
const KEY_ID_PATTERN = /^[a-zA-Z0-9_-]{1,32}$/;

function decodeBase64(value) {
  if (typeof value !== 'string' || !/^[a-zA-Z0-9+/]+={0,2}$/.test(value)) {
    throw new Error('Missing grant signing key');
  }
  return Uint8Array.from(atob(value), c => c.charCodeAt(0));
}
function base64Url(bytes) {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

/** Different domain/version from purchase grants: no receipt and no purchase claim. */
export async function issueTrialGrant(env, { deviceId, startedAtMs, expiresAtMs }, nowMs) {
  if (!validDeviceId(deviceId) || !Number.isSafeInteger(startedAtMs) ||
      !Number.isSafeInteger(expiresAtMs) ||
      expiresAtMs - startedAtMs !== TRIAL_SECONDS * 1000) {
    throw new Error('Invalid trial entitlement');
  }
  const nowSecs = Math.floor(nowMs / 1000);
  const trialEnds = Math.floor(expiresAtMs / 1000);
  const expires = Math.min(nowSecs + OFFLINE_GRANT_SECONDS, trialEnds);
  if (expires <= nowSecs) return null;
  const kid = env?.OFFLINE_GRANT_KEY_ID;
  if (!KEY_ID_PATTERN.test(kid || '') || !env?.OFFLINE_GRANT_PRIVATE_KEY_PKCS8) {
    throw new Error('Trial signing key not configured');
  }
  const claims = {
    v: 2, kind: 'trial', kid, pkg: PACKAGE_NAME, deviceId,
    iat: nowSecs, exp: expires,
    trialStartedAt: Math.floor(startedAtMs / 1000),
    trialExpiresAt: trialEnds,
  };
  const payload = new TextEncoder().encode(JSON.stringify(claims));
  const key = await crypto.subtle.importKey('pkcs8',
    decodeBase64(env.OFFLINE_GRANT_PRIVATE_KEY_PKCS8),
    { name: 'Ed25519' }, false, ['sign']);
  const sig = await crypto.subtle.sign('Ed25519', key, payload);
  return base64Url(payload) + '.' + base64Url(new Uint8Array(sig));
}
