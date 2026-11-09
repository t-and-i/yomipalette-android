import assert from 'node:assert/strict';
import test from 'node:test';
import { handleRtdn } from '../src/rtdn.js';
import { verifyPubSubToken } from '../src/pubsub-auth.js';
import { tokenHash } from '../src/revocations.js';
import { handleRequest } from '../src/worker.js';
import { PACKAGE_NAME, PRODUCT_ID } from '../src/play-api.js';

const NOW = Date.parse('2026-11-04T02:00:00Z');
const TOKEN = 'rtdn-test-purchase-token-123';
const SUB = 'projects/tts-text-mp3/subscriptions/test-rtdn';
const AUD = 'https://rtdn.example.test/rtdn';
const EMAIL = 'rtdn-push@tts-text-mp3.iam.gserviceaccount.com';
const env = () => ({
  RTDN_OIDC_AUDIENCE: AUD,
  RTDN_PUSH_SERVICE_ACCOUNT_EMAIL: EMAIL,
  RTDN_PUBSUB_SUBSCRIPTION: SUB,
  ENTITLEMENTS_DB: new FakeD1(),
});

class FakeD1 {
  constructor() {
    this.revoked = new Map();
    this.completedAt = null;
  }
  prepare(sql) {
    if (!sql.includes('INSERT INTO revoked_purchase_tokens')) throw new Error('Unexpected SQL');
    return { bind: (hash, at) => ({
      run: async () => {
        this.revoked.set(hash, Math.max(this.revoked.get(hash) ?? 0, at));
        return { success: true };
      },
    }) };
  }
}

function notification(record) {
  return { version: '1.0', packageName: PACKAGE_NAME,
    eventTimeMillis: String(NOW - 2000), ...record };
}
function push(payload, { subscription = SUB, auth = 'Bearer good' } = {}) {
  return new Request(AUD, { method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: auth },
    body: JSON.stringify({ subscription, message: {
      messageId: 'test-message-1',
      data: Buffer.from(JSON.stringify(payload), 'utf8').toString('base64'),
    } }),
  });
}
const allowed = () => true;
const dependencies = { verifyToken: allowed, now: () => NOW,
  getAccessToken: async () => 'fake-access-token' };

test('signed Google OIDC JWT requires matching audience, email, expiry and signature', async () => {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true, ['sign', 'verify']);
  const jwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
  jwk.kid = 'test-signing-key';
  const base64url = (data) => Buffer.from(data).toString('base64url');
  const makeJwt = async (overrides = {}) => {
    const header = base64url(JSON.stringify({ alg: 'RS256', kid: jwk.kid }));
    const claims = base64url(JSON.stringify({
      iss: 'https://accounts.google.com', aud: AUD, email: EMAIL,
      email_verified: true, iat: NOW / 1000 - 60,
      exp: NOW / 1000 + 3600, ...overrides,
    }));
    const toSign = header + '.' + claims;
    const signature = await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5', pair.privateKey, new TextEncoder().encode(toSign));
    return toSign + '.' + base64url(signature);
  };
  const options = { audience: AUD, serviceAccountEmail: EMAIL, now: () => NOW,
    loadKey: async () => jwk };
  const good = await makeJwt();
  assert.equal(await verifyPubSubToken('Bearer ' + good, options), true);
  assert.equal(await verifyPubSubToken('Bearer ' + good, { ...options, audience: 'wrong' }), false);
  assert.equal(await verifyPubSubToken('Bearer ' + good, { ...options, serviceAccountEmail: 'wrong' }), false);
  assert.equal(await verifyPubSubToken('Bearer ' + await makeJwt({ email_verified: false }), options), false);
  assert.equal(await verifyPubSubToken('Bearer ' + await makeJwt({ exp: NOW / 1000 - 100 }), options), false);
  assert.equal(await verifyPubSubToken('Bearer ' + good.slice(0, -2) + 'XX', options), false);
  assert.equal(await verifyPubSubToken('Bearer nonsense', options), false);
});

test('unauthenticated and misconfigured RTDNs are denied without database writes', async () => {
  const body = notification({ testNotification: { version: '1.0' } });
  assert.equal((await handleRtdn(push(body), {}, dependencies)).status, 503);
  assert.equal((await handleRtdn(push(body), env(), {
    ...dependencies, verifyToken: () => false })).status, 401);
  assert.equal((await handleRtdn(push(body), env(), {
    ...dependencies, verifyToken: () => { throw new Error('Google JWKS unavailable'); }
  })).status, 503);
});

test('full one-time void revokes only a token hash, safely handles duplicate deliveries', async () => {
  const e = env();
  const payload = notification({ voidedPurchaseNotification: {
    purchaseToken: TOKEN, productType: 2, refundType: 1,
  } });
  for (let i = 0; i < 2; i++) {
    const response = await handleRtdn(push(payload), e, dependencies);
    assert.equal(response.status, 204);
  }
  const hash = await tokenHash(TOKEN);
  assert.equal(e.ENTITLEMENTS_DB.revoked.size, 1);
  assert.equal(e.ENTITLEMENTS_DB.revoked.get(hash), NOW - 2000);
  assert.equal(e.ENTITLEMENTS_DB.revoked.has(TOKEN), false);
  assert.equal(e.ENTITLEMENTS_DB.completedAt, null);
});

test('purchase notifications never grant entitlement and unrelated apps are ignored', async () => {
  const e = env();
  const purchased = notification({ oneTimeProductNotification: {
    notificationType: 1, purchaseToken: TOKEN, sku: PRODUCT_ID,
  } });
  assert.equal((await handleRtdn(push(purchased), e, dependencies)).status, 204);
  assert.equal((await handleRtdn(push({ ...purchased, packageName: 'other.app' }), e, dependencies)).status, 204);
  assert.equal((await handleRtdn(push(notification({ testNotification: {} })), e, dependencies)).status, 204);
  assert.equal(e.ENTITLEMENTS_DB.revoked.size, 0);
});

test('cancelled purchases consult Google Play before changing entitlement', async () => {
  const canceled = notification({ oneTimeProductNotification: {
    notificationType: 2, purchaseToken: TOKEN, sku: PRODUCT_ID,
  } });
  for (const [state, expectedStatus, expectedRevocations] of [
    ['verified', 204, 0], ['rejected', 204, 1],
    ['unavailable', 503, 0],
  ]) {
    const e = env();
    const response = await handleRtdn(push(canceled), e, {
      ...dependencies, lookup: async () => state,
    });
    assert.equal(response.status, expectedStatus);
    assert.equal(e.ENTITLEMENTS_DB.revoked.size, expectedRevocations);
  }
});

test('partial refunds require a current status and full refunds do not call Google', async () => {
  const partial = notification({ voidedPurchaseNotification: {
    purchaseToken: TOKEN, productType: 2, refundType: 2,
  } });
  const e = env();
  let calls = 0;
  const response = await handleRtdn(push(partial), e, {
    ...dependencies, lookup: async () => { calls++; return 'verified'; },
  });
  assert.equal(response.status, 204);
  assert.equal(calls, 1);
  assert.equal(e.ENTITLEMENTS_DB.revoked.size, 0);
  const full = notification({ voidedPurchaseNotification: {
    purchaseToken: TOKEN, productType: 2, refundType: 1,
  } });
  assert.equal((await handleRtdn(push(full), e, {
    ...dependencies, getAccessToken: async () => { throw new Error('Not needed'); },
  })).status, 204);
  assert.equal(e.ENTITLEMENTS_DB.revoked.size, 1);
});

test('wrong subscriptions, broken envelopes and unavailable storage are never acknowledged as success', async () => {
  const full = notification({ voidedPurchaseNotification: {
    purchaseToken: TOKEN, productType: 2, refundType: 1,
  } });
  assert.equal((await handleRtdn(push(full, { subscription: 'wrong' }), env(), dependencies)).status, 400);
  assert.equal((await handleRtdn(new Request(AUD, { method: 'POST',
    headers: { Authorization: 'Bearer good', 'Content-Type': 'application/json' },
    body: '{bad json',
  }), env(), dependencies)).status, 400);
  assert.equal((await handleRtdn(push(full), { ...env(), ENTITLEMENTS_DB: null }, dependencies)).status, 503);
  assert.equal((await handleRtdn(push(notification({ voidedPurchaseNotification: {
    purchaseToken: 'bad', productType: 2, refundType: 1,
  } })), env(), dependencies)).status, 400);
});

test('existing Worker routes /rtdn separately and refuses unconfigured pushes', async () => {
  const response = await handleRequest(push(notification({ testNotification: {} })), {});
  assert.equal(response.status, 503);
});
