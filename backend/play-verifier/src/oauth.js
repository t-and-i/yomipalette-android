const GOOGLE_TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
const GOOGLE_SCOPE = 'https://www.googleapis.com/auth/androidpublisher';

function base64url(bytes) {
  let value = '';
  for (const byte of bytes) value += String.fromCharCode(byte);
  return btoa(value).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function pkcs8FromPem(pem) {
  if (typeof pem !== 'string' || !pem.includes('BEGIN PRIVATE KEY')) {
    throw new Error('Service account key is not configured.');
  }
  const value = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '');
  return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
}

export async function createAssertion(account, currentMs = Date.now()) {
  if (
    !account ||
    typeof account.client_email !== 'string' ||
    !account.client_email.endsWith('.gserviceaccount.com')
  ) {
    throw new Error('Service account email is missing or invalid.');
  }
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pkcs8FromPem(account.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const now = Math.floor(currentMs / 1000);
  const header = base64url(new TextEncoder().encode(JSON.stringify({
    alg: 'RS256',
    typ: 'JWT',
  })));
  const payload = base64url(new TextEncoder().encode(JSON.stringify({
    iss: account.client_email,
    scope: GOOGLE_SCOPE,
    aud: GOOGLE_TOKEN_ENDPOINT,
    iat: now,
    exp: now + 3600,
  })));
  const toSign = `${header}.${payload}`;
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(toSign),
  );
  return `${toSign}.${base64url(new Uint8Array(signature))}`;
}

/** Never log the secret JSON or the OAuth assertion. */
export async function getPlayAccessToken(env, {
  fetchImpl = fetch,
  now = Date.now,
} = {}) {
  if (!env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON) {
    throw new Error('Google Play service account not configured.');
  }
  let account;
  try {
    account = JSON.parse(env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON);
  } catch {
    throw new Error('Service account secret is not valid JSON.');
  }
  const assertion = await createAssertion(account, now());
  const response = await fetchImpl(GOOGLE_TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) {
    throw new Error('Google OAuth token request failed.');
  }
  const result = await response.json();
  if (
    typeof result?.access_token !== 'string' ||
    result.access_token.length < 10
  ) {
    throw new Error('Google OAuth token response invalid.');
  }
  return result.access_token;
}
