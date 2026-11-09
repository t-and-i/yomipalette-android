// Validate Google Pub/Sub authenticated push OIDC JWTs before trusting RTDN.
const JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const CACHE_MS = 60 * 60 * 1000;
const SKEW_SECONDS = 300;
const cache = { expires: 0, keys: [] };

function decode64(value) {
  if (!/^[A-Za-z0-9_-]+$/.test(value) || value.length > 16000) {
    throw new Error('Invalid JWT encoding');
  }
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '='));
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function decodeJson(value) {
  return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(decode64(value)));
}

async function googleKey(kid, fetchImpl, now) {
  if (cache.expires > now && cache.keys.length) {
    const existing = cache.keys.find((item) => item.kid === kid);
    if (existing) return existing;
  }
  const response = await fetchImpl(JWKS_URL, {
    method: 'GET',
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error('Pub/Sub signing keys unavailable');
  const jwks = await response.json();
  if (!Array.isArray(jwks?.keys) || jwks.keys.length > 32) {
    throw new Error('Pub/Sub signing keys invalid');
  }
  cache.keys = jwks.keys;
  cache.expires = now + CACHE_MS;
  return cache.keys.find((item) => item.kid === kid);
}

/**
 * Authentication failure returns false. A failed signing-key request throws,
 * so Pub/Sub can retry rather than permanently losing an authentic event.
 */
export async function verifyPubSubToken(headerValue, {
  audience, serviceAccountEmail,
  fetchImpl = fetch,
  now = Date.now,
  loadKey = googleKey,
} = {}) {
  if (!audience || !serviceAccountEmail) return false;
  const match = /^Bearer ([A-Za-z0-9_.-]+)$/.exec(headerValue || '');
  if (!match || match[1].length > 16000) return false;
  try {
    const parts = match[1].split('.');
    if (parts.length !== 3) return false;
    const header = decodeJson(parts[0]);
    const claims = decodeJson(parts[1]);
    if (header?.alg !== 'RS256' || typeof header.kid !== 'string' ||
        header.kid.length < 1 || header.kid.length > 256) return false;
    const seconds = Math.floor(now() / 1000);
    if (claims?.aud !== audience || claims?.email !== serviceAccountEmail ||
        claims?.email_verified !== true ||
        !['accounts.google.com', 'https://accounts.google.com'].includes(claims?.iss) ||
        !Number.isFinite(claims?.iat) || !Number.isFinite(claims?.exp) ||
        claims.iat > seconds + SKEW_SECONDS ||
        claims.exp <= seconds - 30 ||
        claims.exp <= claims.iat ||
        claims.exp - claims.iat > 7200) return false;

    const jwk = await loadKey(header.kid, fetchImpl, now());
    if (!jwk || jwk.kty !== 'RSA') return false;
    const key = await crypto.subtle.importKey('jwk', jwk,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
    return crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      key,
      decode64(parts[2]),
      new TextEncoder().encode(parts[0] + '.' + parts[1]),
    );
  } catch (error) {
    // Retry on Google signing-key outages; malformed tokens stay unauthorized.
    if (error?.message === 'Pub/Sub signing keys unavailable' ||
        error?.message === 'Pub/Sub signing keys invalid') throw error;
    return false;
  }
}
