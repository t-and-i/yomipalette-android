import assert from 'node:assert/strict';
import test from 'node:test';

import { handleRequest } from '../src/worker.js';
import { allowVerifyIp, allowVerifyToken } from '../src/rate-limits.js';
import { tokenHash } from '../src/revocations.js';
import { PACKAGE_NAME, PRODUCT_ID } from '../src/play-api.js';

const TOKEN = 'test-rate-limit-purchase-token-12345';

function request({ token = TOKEN, ip = '198.51.100.10', otherHeaders = {} } = {}) {
  return new Request('https://verify.example.test/verify', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'CF-Connecting-IP': ip,
      ...otherHeaders,
    },
    body: JSON.stringify({
      packageName: PACKAGE_NAME,
      productId: PRODUCT_ID,
      purchaseToken: token,
      requestId: 'a'.repeat(32),
      integrityToken: 'mock-integrity-token',
    }),
  });
}

function env(ipLimit, tokenLimit) {
  return {
    VERIFY_IP_RATE_LIMIT: { limit: ipLimit },
    VERIFY_TOKEN_RATE_LIMIT: { limit: tokenLimit },
    // Deliberately no D1: a throttled request must exit first.
  };
}

test('per-IP limiter returns 429 before touching tokens, D1, or Google', async () => {
  const keys = [];
  const e = env(async ({ key }) => { keys.push(key); return { success: false }; },
    async () => { throw new Error('Token limiter must not be reached'); });
  const response = await handleRequest(request(), e);
  assert.equal(response.status, 429);
  assert.deepEqual(await response.json(), { status: 'unavailable' });
  assert.equal(response.headers.get('Retry-After'), '60');
  assert.deepEqual(keys, ['ip:198.51.100.10']);
  assert.equal(keys.join('').includes(TOKEN), false);
});

test('purchase-token limiter uses only a SHA-256 hash', async () => {
  const keys = [];
  const e = env(async () => ({ success: true }), async ({ key }) => {
    keys.push(key);
    return { success: false };
  });
  const response = await handleRequest(request(), e);
  assert.equal(response.status, 429);
  assert.equal(keys.length, 1);
  assert.equal(keys[0], 'token:' + await tokenHash(TOKEN));
  assert.equal(keys[0].includes(TOKEN), false);
  assert.equal((await response.text()).includes(TOKEN), false);
});

test('invalid purchase data is rejected without using token limiter', async () => {
  let calls = 0;
  const e = env(async () => ({ success: true }),
    async () => { calls++; return { success: true }; });
  const result = await handleRequest(request({ token: 'bad' }), e);
  assert.equal(result.status, 400);
  assert.equal(calls, 0);
});

test('missing or failed rate limit binding fails closed, never contacts Google', async () => {
  const cases = [
    {},
    { VERIFY_IP_RATE_LIMIT: { limit: async () => ({ success: true }) } },
    env(async () => { throw new Error('simulated backend error'); },
      async () => ({ success: true })),
    env(async () => ({ success: true }),
      async () => { throw new Error('simulated backend error'); }),
    env(async () => ({}), async () => ({ success: true })),
  ];
  for (const item of cases) {
    const response = await handleRequest(request(), item, {
      getAccessToken: async () => { throw new Error('Google must not be called'); },
    });
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { status: 'unavailable' });
  }
});

test('client supplied X-Forwarded-For is ignored in favor of CF-Connecting-IP', async () => {
  const keys = [];
  await allowVerifyIp({
    VERIFY_IP_RATE_LIMIT: { limit: async ({ key }) => {
      keys.push(key);
      return { success: true };
    } },
  }, request({ otherHeaders: { 'X-Forwarded-For': '203.0.113.200' } }));
  assert.deepEqual(keys, ['ip:198.51.100.10']);
});

test('missing or malformed Cloudflare IP shares a bounded fallback bucket', async () => {
  const keys = [];
  const e = { VERIFY_IP_RATE_LIMIT: { limit: async ({ key }) => {
    keys.push(key);
    return { success: true };
  } } };
  await allowVerifyIp(e, new Request('https://verify.example.test/verify'));
  await allowVerifyIp(e, request({ ip: 'invalid-alias.example' }));
  assert.deepEqual(keys, ['ip:unavailable', 'ip:unavailable']);
});

test('reject malformed token digests before invoking limiter', async () => {
  let count = 0;
  const e = {
    VERIFY_TOKEN_RATE_LIMIT: { limit: async () => {
      count++;
      return { success: true };
    } },
  };
  await assert.rejects(allowVerifyToken(e, TOKEN), /Invalid purchase-token digest/);
  assert.equal(count, 0);
});
