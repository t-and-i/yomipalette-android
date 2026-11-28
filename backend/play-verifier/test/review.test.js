import assert from 'node:assert/strict';
import test from 'node:test';
import { handleRequest } from '../src/worker.js';
import { PACKAGE_NAME } from '../src/play-api.js';
import { tokenHash } from '../src/revocations.js';
import faultWorker from '../test-support/review-fault-worker.js';

async function scenario() {
  const keys = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  const rows = new Map();
  const env = {
    REVIEW_ACCESS_TOKEN: 'test-only-' + 'a'.repeat(43),
    OFFLINE_GRANT_KEY_ID: 'review-test',
    OFFLINE_GRANT_PRIVATE_KEY_PKCS8: Buffer.from(
      await crypto.subtle.exportKey('pkcs8', keys.privateKey)).toString('base64'),
    VERIFY_IP_RATE_LIMIT: { limit: async () => ({ success: true }) },
    VERIFY_TOKEN_RATE_LIMIT: { limit: async () => ({ success: true }) },
    ENTITLEMENTS_DB: { prepare: sql => ({ bind: (...args) => ({
      run: async () => {
        assert.match(sql, /^INSERT INTO review_installations/);
        rows.set(args[0], { device_id: args[1], revoked_at_ms: null });
      },
      first: async () => {
        assert.match(sql, /^SELECT device_id/);
        return rows.get(args[0]) ?? null;
      },
    }) }) },
  };
  let now = Date.parse('2026-11-28T00:00:00Z');
  const request = (body, method = 'POST') => handleRequest(new Request('https://example.test/review', {
    method, headers: { 'Content-Type': 'application/json' },
    ...(method === 'POST' ? { body: JSON.stringify({ packageName: PACKAGE_NAME,
      deviceId: 'a'.repeat(43), ...body }) } : {}),
  }), env, { now: () => now });
  return { env, rows, keys, request, advance: ms => { now += ms; } };
}

test('review registration, offline scope, renewal, device binding and revocation', async () => {
  const s = await scenario();
  const response = await s.request({ action: 'register', token: s.env.REVIEW_ACCESS_TOKEN });
  assert.equal(response.status, 200);
  assert.match(response.headers.get('cache-control'), /no-store/);
  const registration = await response.json();
  assert.match(registration.credential, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(s.rows.has(registration.credential), false);
  const [payload, signature] = registration.grant.split('.').map(x => Buffer.from(x, 'base64url'));
  assert.equal(await crypto.subtle.verify('Ed25519', s.keys.publicKey, signature, payload), true);
  const claims = JSON.parse(payload);
  assert.equal(claims.kind, 'review');
  assert.equal(claims.v, 3);
  assert.equal(claims.exp - claims.iat, 72 * 3600);
  assert.equal(claims.productId, undefined);
  s.advance(73 * 3600 * 1000);
  const refresh = { action: 'refresh', credential: registration.credential };
  const renewed = await (await s.request(refresh)).json();
  assert.equal(renewed.status, 'active');
  assert.notEqual(renewed.grant, registration.grant);
  assert.equal((await s.request({ ...refresh, deviceId: 'b'.repeat(43) })).status, 401);
  s.rows.get(await tokenHash(registration.credential)).revoked_at_ms = 1;
  assert.equal((await s.request(refresh)).status, 401);
  // A second reviewer can independently reuse the Console token.
  assert.equal((await s.request({ action: 'register', token: s.env.REVIEW_ACCESS_TOKEN,
    deviceId: 'b'.repeat(43) })).status, 200);
});

test('invalid credentials, rotation, unavailable signer and rate limits fail closed', async () => {
  const s = await scenario();
  assert.equal((await s.request({}, 'GET')).status, 405);
  assert.equal((await s.request({ action: 'register', token: 'wrong' })).status, 401);
  assert.equal(s.rows.size, 0);
  s.env.REVIEW_ACCESS_TOKEN_PREVIOUS = 'previous-' + 'b'.repeat(43);
  assert.equal((await s.request({ action: 'register', token: s.env.REVIEW_ACCESS_TOKEN_PREVIOUS })).status, 200);
  s.env.OFFLINE_GRANT_PRIVATE_KEY_PKCS8 = '';
  assert.equal((await s.request({ action: 'register', token: s.env.REVIEW_ACCESS_TOKEN })).status, 503);
  assert.equal(s.rows.size, 1);
  s.env.VERIFY_IP_RATE_LIMIT.limit = async () => ({ success: false });
  assert.equal((await s.request({ action: 'register', token: s.env.REVIEW_ACCESS_TOKEN })).status, 429);
});

test('staging fault entry replaces authenticated refresh only and preserves normal entry', async () => {
  const s = await scenario();
  s.env.REVIEW_REFRESH_TEST_STATUS = '429';
  const invoke = body => faultWorker.fetch(new Request('https://example.test/review', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ packageName: PACKAGE_NAME, deviceId: 'a'.repeat(43), ...body }),
  }), s.env);
  const registered = await invoke({ action: 'register', token: s.env.REVIEW_ACCESS_TOKEN });
  assert.equal(registered.status, 200);
  const { credential } = await registered.json();
  const refresh = { action: 'refresh', credential };
  assert.equal((await s.request(refresh)).status, 200);
  for (const status of [429, 503]) {
    s.env.REVIEW_REFRESH_TEST_STATUS = String(status);
    const response = await invoke(refresh);
    assert.equal(response.status, status);
    assert.equal(response.headers.get('X-YomiPalette-Test-Fault'), `review-refresh-${status}`);
    assert.deepEqual(await response.json(), { status: 'unavailable' });
  }
  assert.equal((await invoke({ ...refresh, credential: 'b'.repeat(43) })).status, 401);
  delete s.env.REVIEW_REFRESH_TEST_STATUS;
  assert.equal((await invoke(refresh)).status, 200);
});
