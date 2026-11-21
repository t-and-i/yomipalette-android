import { PACKAGE_NAME, SUPPORTED_PRODUCT_IDS } from './play-api.js';

// One refresh grants at most 72 hours of offline access; the client must never
// extend an expiration locally. The key is a Worker secret, never app source.
export const OFFLINE_GRANT_SECONDS = 72 * 60 * 60;
const DEVICE_ID_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const KEY_ID_PATTERN = /^[a-zA-Z0-9_-]{1,32}$/;

export function validDeviceId(value) {
  return typeof value === 'string' && DEVICE_ID_PATTERN.test(value);
}

function decodeBase64(input) {
  if (typeof input !== 'string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(input)) {
    throw new Error('Invalid signing key format.');
  }
  return Uint8Array.from(atob(input), (char) => char.charCodeAt(0));
}

function base64Url(bytes) {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

export async function issueOfflineGrant(env, { productId, deviceId, purchaseTokenHash }, nowMs) {
  if (!validDeviceId(deviceId) || !SUPPORTED_PRODUCT_IDS.has(productId) ||
      !/^[0-9a-f]{64}$/.test(purchaseTokenHash)) {
    throw new Error('Invalid entitlement scope.');
  }
  const kid = env.OFFLINE_GRANT_KEY_ID;
  const secret = env.OFFLINE_GRANT_PRIVATE_KEY_PKCS8;
  if (!KEY_ID_PATTERN.test(kid || '') || !secret) {
    throw new Error('Offline grant signing key is not configured.');
  }
  const issuedAt = Math.floor(nowMs / 1000);
  if (!Number.isSafeInteger(issuedAt) || issuedAt <= 0) {
    throw new Error('Invalid grant clock.');
  }
  const claims = {
    v: 1,
    kid,
    pkg: PACKAGE_NAME,
    productId,
    deviceId,
    receiptHash: purchaseTokenHash,
    iat: issuedAt,
    exp: issuedAt + OFFLINE_GRANT_SECONDS,
  };
  const payload = new TextEncoder().encode(JSON.stringify(claims));
  const key = await crypto.subtle.importKey(
    'pkcs8',
    decodeBase64(secret),
    { name: 'Ed25519' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign('Ed25519', key, payload);
  return base64Url(payload) + '.' + base64Url(new Uint8Array(signature));
}
