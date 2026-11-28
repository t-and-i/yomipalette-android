// Google Identity ID token authentication. Never persist/log tokens or emails.
const JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const CACHE_MS = 3600_000;
const signingKeys = { expiry: 0, keys: [] };

function decode64(s) {
  if (typeof s !== 'string' || s.length > 12000 ||
      !/^[a-zA-Z0-9_-]+$/.test(s)) throw new Error('Invalid JWT encoding');
  return Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')
    .padEnd(Math.ceil(s.length / 4) * 4, '=')), c => c.charCodeAt(0));
}

function decodeJson(s) {
  return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(decode64(s)));
}

async function loadSigningKey(kid, fetchImpl, now) {
  if (now < signingKeys.expiry) {
    const cached = signingKeys.keys.find(k => k.kid === kid);
    if (cached) return cached;
  }
  const response = await fetchImpl(JWKS_URL, { signal: AbortSignal.timeout(8000) });
  if (!response.ok) throw new Error('Google signing keys unavailable');
  const value = await response.json();
  if (!Array.isArray(value?.keys) || value.keys.length < 1 || value.keys.length > 32) {
    throw new Error('Invalid Google signing keys');
  }
  signingKeys.keys = value.keys;
  signingKeys.expiry = now + CACHE_MS;
  return signingKeys.keys.find(k => k.kid === kid);
}

/** Return opaque account subject ONLY after local RS256 signature verification. */
export async function verifyGoogleIdToken(idToken, clientId, {
  fetchImpl = fetch,
  now = Date.now,
  loadKey = loadSigningKey,
} = {}) {
  if (!clientId || typeof clientId !== 'string' ||
      typeof idToken !== 'string' || idToken.length < 80 || idToken.length > 8192) {
    return null;
  }
  try {
    const parts = idToken.split('.');
    if (parts.length !== 3) return null;
    const header = decodeJson(parts[0]);
    const claims = decodeJson(parts[1]);
    if (header?.alg !== 'RS256' || typeof header.kid !== 'string' ||
        header.kid.length < 1 || header.kid.length > 256 ||
        claims?.aud !== clientId ||
        !['accounts.google.com', 'https://accounts.google.com'].includes(claims?.iss) ||
        typeof claims.sub !== 'string' || !/^[0-9]{1,128}$/.test(claims.sub) ||
        !Number.isSafeInteger(claims.iat) || !Number.isSafeInteger(claims.exp)) return null;
    const seconds = Math.floor(now() / 1000);
    if (claims.iat > seconds + 60 || claims.exp <= seconds ||
        claims.exp <= claims.iat || claims.exp - claims.iat > 7200) return null;
    const jwk = await loadKey(header.kid, fetchImpl, now());
    if (!jwk || jwk.kty !== 'RSA' || jwk.alg && jwk.alg !== 'RS256') return null;
    const key = await crypto.subtle.importKey('jwk', jwk,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
    const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key,
      decode64(parts[2]), new TextEncoder().encode(parts[0] + '.' + parts[1]));
    return ok ? claims.sub : null;
  } catch (e) {
    // Retriable signing key outage must not be disguised as a bad identity.
    if (e?.message === 'Google signing keys unavailable' ||
        e?.message === 'Invalid Google signing keys') throw e;
    return null;
  }
}
