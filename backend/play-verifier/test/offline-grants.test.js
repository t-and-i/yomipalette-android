import assert from 'node:assert/strict';
import test from 'node:test';
import { generateKeyPairSync, verify as verifyEd25519 } from 'node:crypto';

import { handleRequest } from '../src/worker.js';
import { PACKAGE_NAME, PRODUCT_ID } from '../src/play-api.js';
import { tokenHash } from '../src/revocations.js';
import { OFFLINE_GRANT_SECONDS, issueOfflineGrant } from '../src/offline-grants.js';

const NOW = Date.parse('2026-11-21T12:00:00Z');
const TOKEN = 'a-valid-play-purchase-token';
const DEVICE_ID = 'A'.repeat(43);
const REQUEST_ID = 'b'.repeat(32);
const { privateKey, publicKey } = generateKeyPairSync('ed25519');
const SIGNER = {
  OFFLINE_GRANT_PRIVATE_KEY_PKCS8: privateKey.export({
    format: 'der', type: 'pkcs8',
  }).toString('base64'),
  OFFLINE_GRANT_KEY_ID: 'test-2026q4',
};

function decodeGrant(grant) {
  const [a, b] = grant.split('.');
  assert.ok(a && b);
  const payload = Buffer.from(a, 'base64url');
  const signature = Buffer.from(b, 'base64url');
  assert.equal(verifyEd25519(null, payload, publicKey, signature), true);
  return JSON.parse(payload.toString('utf8'));
}

function makeRequest({ productId = PRODUCT_ID, deviceId = DEVICE_ID, token = TOKEN, legacy = false } = {}) {
  return new Request('https://verify.example/verify', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      packageName: PACKAGE_NAME,
      productId,
      purchaseToken: token,
      requestId: REQUEST_ID,
      integrityToken: 'fake-integrity-proof',
      ...(legacy ? {} : { deviceId }),
    }),
  });
}

function context({ productId = PRODUCT_ID, deviceId = DEVICE_ID, signer = true,
  googleStatus = 'PURCHASED', revoked = false, integrityDevice = deviceId,
  legacy = false } = {}) {
  let googleCalls = 0;
  const expectedHash = async () => tokenHash(JSON.stringify(legacy
    ? ['yomipalette:/verify:v1', PACKAGE_NAME, productId, await tokenHash(TOKEN), REQUEST_ID]
    : ['yomipalette:/verify:v2', PACKAGE_NAME, productId, await tokenHash(TOKEN), REQUEST_ID, integrityDevice]));
  const env = {
    ENTITLEMENTS_DB: {
      prepare: (sql) => ({
        bind: () => ({
          first: async () => sql.includes('FROM sync_state')
            ? { completed_at_ms: NOW - 1000 }
            : revoked ? { token_hash: await tokenHash(TOKEN) } : null,
        }),
      }),
    },
    VERIFY_IP_RATE_LIMIT: { limit: async () => ({ success: true }) },
    VERIFY_TOKEN_RATE_LIMIT: { limit: async () => ({ success: true }) },
    ...(signer ? SIGNER : {}),
  };
  const deps = {
    now: () => NOW,
    getAccessToken: async () => 'fake-access-token',
    fetchImpl: async (url) => {
      if (String(url).endsWith(':decodeIntegrityToken')) {
        return Response.json({
          tokenPayloadExternal: {
            requestDetails: {
              requestPackageName: PACKAGE_NAME,
              requestHash: await expectedHash(),
              timestampMillis: String(NOW),
            },
            appIntegrity: { appRecognitionVerdict: 'PLAY_RECOGNIZED', packageName: PACKAGE_NAME },
            accountDetails: { appLicensingVerdict: 'LICENSED' },
            deviceIntegrity: { deviceRecognitionVerdict: ['MEETS_DEVICE_INTEGRITY'] },
          },
        });
      }
      googleCalls++;
      return Response.json({
        purchaseStateContext: { purchaseState: googleStatus },
        productLineItem: [{
          productId,
          productOfferDetails: {
            consumptionState: 'CONSUMPTION_STATE_YET_TO_BE_CONSUMED',
            refundableQuantity: 1,
          },
        }],
      });
    },
  };
  return { env, deps, get googleCalls() { return googleCalls; } };
}

test('Ed25519 grant includes strict scope, purchase hash and 72-hour expiry', async () => {
  const ctx = context();
  const response = await handleRequest(makeRequest(), ctx.env, ctx.deps);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.status, 'verified');
  const claims = decodeGrant(body.offlineGrant);
  assert.deepEqual(claims, {
    v: 1, kid: 'test-2026q4', pkg: PACKAGE_NAME,
    productId: PRODUCT_ID, deviceId: DEVICE_ID,
    receiptHash: await tokenHash(TOKEN),
    iat: NOW / 1000, exp: NOW / 1000 + OFFLINE_GRANT_SECONDS,
  });
  assert.equal(ctx.googleCalls, 1);
  assert.equal(response.headers.get('Cache-Control'), 'no-store, private');
  assert.equal(response.bodyUsed, true);
});

test('retired remove_ads product is rejected without granting entitlement', async () => {
  const ctx = context();
  const response = await handleRequest(
    makeRequest({ productId: 'remove_ads' }), ctx.env, ctx.deps,
  );
  assert.equal(response.status, 400);
  assert.equal(ctx.googleCalls, 0);
});

test('v1 clients retain existing verified response without offline fields', async () => {
  const ctx = context({ legacy: true });
  const result = await handleRequest(makeRequest({ legacy: true }), ctx.env, ctx.deps);
  assert.deepEqual(await result.json(), { status: 'verified' });
});

test('fail closed on invalid deviceId, wrong Play Integrity binding or signing outage', async () => {
  for (const bad of ['invalid', 'B'.repeat(44), '', null]) {
    const ctx = context();
    const response = await handleRequest(makeRequest({ deviceId: bad }), ctx.env, ctx.deps);
    assert.equal(response.status, 400);
    assert.equal(ctx.googleCalls, 0);
  }
  const ctxTampered = context({ integrityDevice: 'Z'.repeat(43) });
  const tampered = await handleRequest(makeRequest(), ctxTampered.env, ctxTampered.deps);
  assert.equal(tampered.status, 503);
  assert.equal(ctxTampered.googleCalls, 0);

  const ctxNoSigner = context({ signer: false });
  const unsigned = await handleRequest(makeRequest(), ctxNoSigner.env, ctxNoSigner.deps);
  assert.equal(unsigned.status, 503);
  assert.deepEqual(await unsigned.json(), { status: 'unavailable' });
});

test('refunded purchases and Play pending status never receive signed grants', async () => {
  const revoked = context({ revoked: true });
  const denied = await handleRequest(makeRequest(), revoked.env, revoked.deps);
  assert.deepEqual(await denied.json(), { status: 'rejected' });
  assert.equal(revoked.googleCalls, 0);

  const pending = context({ googleStatus: 'PENDING' });
  const result = await handleRequest(makeRequest(), pending.env, pending.deps);
  assert.deepEqual(await result.json(), { status: 'rejected' });
  assert.equal(pending.googleCalls, 1);
});

test('invalid signer configuration cannot issue a grant', async () => {
  const ctx = context();
  await assert.rejects(issueOfflineGrant(
    { OFFLINE_GRANT_KEY_ID: 'test' },
    { productId: PRODUCT_ID, deviceId: DEVICE_ID,
      purchaseTokenHash: await tokenHash(TOKEN) }, NOW,
  ));
  const valid = await issueOfflineGrant(ctx.env, {
    productId: PRODUCT_ID, deviceId: DEVICE_ID,
    purchaseTokenHash: await tokenHash(TOKEN),
  }, NOW);
  assert.equal(decodeGrant(valid).exp, NOW / 1000 + 259200);
});

test('diagnostic logging is opt-in, fixed-code only, and never reveals identities', async () => {
  const messages = [];
  const original = console.info;
  console.info = (msg) => messages.push(msg);
  try {
    const disabled = context();
    await handleRequest(makeRequest(), disabled.env, disabled.deps);
    assert.deepEqual(messages, []);

    const enabled = context();
    enabled.env.OFFLINE_GRANT_DIAGNOSTICS = '1';
    assert.equal((await handleRequest(makeRequest(), enabled.env, enabled.deps)).status, 200);

    const legacy = context({ legacy: true });
    legacy.env.OFFLINE_GRANT_DIAGNOSTICS = '1';
    assert.equal((await handleRequest(makeRequest({ legacy: true }), legacy.env, legacy.deps)).status, 200);

    const missing = context({ signer: false });
    missing.env.OFFLINE_GRANT_DIAGNOSTICS = '1';
    assert.equal((await handleRequest(makeRequest(), missing.env, missing.deps)).status, 503);
    assert.deepEqual(messages, [
      'YP_ENTITLEMENT_WORKER grant_issued',
      'YP_ENTITLEMENT_WORKER verified_without_device',
      'YP_ENTITLEMENT_WORKER grant_signing_failed',
    ]);
    for (const msg of messages) {
      assert.equal(msg.includes(TOKEN), false);
      assert.equal(msg.includes(DEVICE_ID), false);
      assert.equal(msg.includes(SIGNER.OFFLINE_GRANT_PRIVATE_KEY_PKCS8), false);
    }
  } finally {
    console.info = original;
  }
});
