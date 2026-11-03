import assert from 'node:assert/strict';
import test from 'node:test';

import { createAssertion, getPlayAccessToken } from '../src/oauth.js';

function unbase64url(value) {
  const encoded = value.replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(encoded), (char) => char.charCodeAt(0));
}

test('service account JWT is properly RS256-signed and scoped', async () => {
  const keys = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify'],
  );
  const privateKey = new Uint8Array(await crypto.subtle.exportKey('pkcs8', keys.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...privateKey))}\n-----END PRIVATE KEY-----\n`;
  const account = {
    client_email: 'test-application@test-project.iam.gserviceaccount.com',
    private_key: pem,
  };
  const now = Date.parse('2026-11-04T00:00:00Z');
  const jwt = await createAssertion(account, now);
  const [headerB64, payloadB64, signatureB64] = jwt.split('.');
  assert.equal(JSON.parse(new TextDecoder().decode(unbase64url(headerB64))).alg, 'RS256');
  const payload = JSON.parse(new TextDecoder().decode(unbase64url(payloadB64)));
  assert.equal(payload.iss, account.client_email);
  assert.equal(payload.scope, 'https://www.googleapis.com/auth/androidpublisher');
  assert.equal(payload.exp - payload.iat, 3600);
  const signatureValid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    keys.publicKey,
    unbase64url(signatureB64),
    new TextEncoder().encode(`${headerB64}.${payloadB64}`),
  );
  assert.equal(signatureValid, true);

  const result = await getPlayAccessToken(
    { GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: JSON.stringify(account) },
    {
      now: () => now,
      fetchImpl: async (url, options) => {
        assert.equal(url, 'https://oauth2.googleapis.com/token');
        assert.equal(options.method, 'POST');
        assert.equal(options.body.get('assertion'), jwt);
        return new Response(JSON.stringify({
          access_token: 'fake-access-token-for-test-only',
        }), { status: 200 });
      },
    },
  );
  assert.equal(result, 'fake-access-token-for-test-only');

  // Account-level Secrets Store bindings resolve secrets asynchronously.
  let secretReads = 0;
  const fromStore = await getPlayAccessToken(
    { GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: {
      async get() {
        secretReads++;
        return JSON.stringify(account);
      },
    } },
    {
      now: () => now,
      fetchImpl: async (_url, options) => {
        assert.equal(options.body.get('assertion'), jwt);
        return new Response(JSON.stringify({
          access_token: 'fake-access-token-for-test-only',
        }), { status: 200 });
      },
    },
  );
  assert.equal(fromStore, 'fake-access-token-for-test-only');
  assert.equal(secretReads, 1);
});

test('missing service account or Google OAuth failure does not leak secret', async () => {
  await assert.rejects(
    getPlayAccessToken({}, { fetchImpl: async () => { throw new Error('unused'); } }),
    /not configured/,
  );
  const account = {
    client_email: 'test@test-project.iam.gserviceaccount.com',
    private_key: 'INVALID',
  };
  await assert.rejects(
    createAssertion(account),
    /not configured/,
  );
});

test('Secrets Store failures and invalid values never call Google', async () => {
  let calls = 0;
  const failFetch = async () => {
    calls++;
    throw new Error('Google API must not be called.');
  };
  for (const binding of [
    { async get() { throw new Error('sensitive test detail'); } },
    { async get() { return null; } },
    { async get() { return '{invalid-json'; } },
    { async get() { return 42; } },
    {},
  ]) {
    await assert.rejects(
      getPlayAccessToken(
        { GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: binding },
        { fetchImpl: failFetch },
      ),
      /service account|secret/i,
    );
  }
  assert.equal(calls, 0);
});
