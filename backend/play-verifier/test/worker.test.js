import assert from 'node:assert/strict';
import test from 'node:test';

import { handleRequest, runScheduledSync } from '../src/worker.js';
import { PACKAGE_NAME, PRODUCT_ID } from '../src/play-api.js';
import { tokenHash } from '../src/revocations.js';

const NOW = Date.parse('2026-11-04T00:00:00.000Z');
const TOKEN = 'valid-purchase-test-token-123456';

class FakeD1 {
  constructor({ fresh = true } = {}) {
    this.completedAt = fresh ? NOW - 3600_000 : null;
    this.revoked = new Map();
  }

  prepare(statement) {
    return {
      bind: (...values) => ({
        first: async () => {
          if (statement.includes('FROM sync_state')) {
            return this.completedAt === null
              ? null
              : { completed_at_ms: this.completedAt };
          }
          if (statement.includes('FROM revoked_purchase_tokens')) {
            return this.revoked.has(values[0])
              ? { token_hash: values[0] }
              : null;
          }
          throw new Error('Unexpected SQL read');
        },
        run: async () => {
          if (statement.includes('INSERT INTO revoked_purchase_tokens')) {
            this.revoked.set(values[0], values[1]);
          } else if (statement.includes('INSERT INTO sync_state')) {
            this.completedAt = values[1];
          } else {
            throw new Error('Unexpected SQL write');
          }
          return { success: true };
        },
      }),
    };
  }
}

function purchase({ state = 'PURCHASED', id = PRODUCT_ID, refundable = 1 } = {}) {
  return {
    purchaseStateContext: { purchaseState: state },
    productLineItem: [
      {
        productId: id,
        productOfferDetails: {
          consumptionState: 'CONSUMPTION_STATE_YET_TO_BE_CONSUMED',
          refundableQuantity: refundable,
        },
      },
    ],
    acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING',
  };
}

function request(data = {}) {
  return new Request('https://verify.example.com/verify', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      packageName: PACKAGE_NAME,
      productId: PRODUCT_ID,
      purchaseToken: TOKEN,
      ...data,
    }),
  });
}

function setup({ db = new FakeD1(), googleBody = purchase(), googleStatus = 200 } = {}) {
  let calls = 0;
  const dependencies = {
    now: () => NOW,
    getAccessToken: async () => 'test-only-access-token',
    fetchImpl: async (url, options) => {
      calls++;
      assert.match(String(url), /productsv2\/tokens\//);
      assert.match(options.headers.Authorization, /^Bearer /);
      return new Response(JSON.stringify(googleBody), { status: googleStatus });
    },
  };
  return {
    env: { ENTITLEMENTS_DB: db },
    dependencies,
    get calls() { return calls; },
  };
}

test('real Play PURCHASED state with correct product returns verified', async () => {
  const ctx = setup();
  const response = await handleRequest(request(), ctx.env, ctx.dependencies);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: 'verified' });
  assert.equal(ctx.calls, 1);
  assert.match(response.headers.get('Cache-Control'), /no-store/);
});

test('invalid package/product fails before Google API call', async () => {
  const ctx = setup();
  for (const data of [
    { packageName: 'fake.package' },
    { productId: 'other_product' },
    { purchaseToken: 'short' },
  ]) {
    const res = await handleRequest(request(data), ctx.env, ctx.dependencies);
    assert.equal(res.status, 400);
  }
  assert.equal(ctx.calls, 0);
});

test('pending/cancelled purchases and wrong products are rejected', async () => {
  for (const googleBody of [
    purchase({ state: 'PENDING' }),
    purchase({ state: 'CANCELLED' }),
    purchase({ id: 'different_item' }),
    purchase({ refundable: 0 }),
  ]) {
    const ctx = setup({ googleBody });
    const res = await handleRequest(request(), ctx.env, ctx.dependencies);
    assert.deepEqual(await res.json(), { status: 'rejected' });
  }
});

test('Google invalid tokens are rejected, but outages fail closed', async () => {
  for (const googleStatus of [400, 404, 410]) {
    const ctx = setup({ googleStatus });
    const res = await handleRequest(request(), ctx.env, ctx.dependencies);
    assert.deepEqual(await res.json(), { status: 'rejected' });
  }
  for (const googleStatus of [401, 403, 429, 500, 503]) {
    const ctx = setup({ googleStatus });
    const res = await handleRequest(request(), ctx.env, ctx.dependencies);
    assert.equal(res.status, 503);
    assert.deepEqual(await res.json(), { status: 'unavailable' });
  }
});

test('stale or uninitialized revocation state blocks entitlement', async () => {
  const ctx = setup({ db: new FakeD1({ fresh: false }) });
  const response = await handleRequest(request(), ctx.env, ctx.dependencies);
  assert.equal(response.status, 503);
  assert.equal(ctx.calls, 0);
});

test('revoked purchase is rejected without querying Google', async () => {
  const db = new FakeD1();
  db.revoked.set(await tokenHash(TOKEN), NOW);
  const ctx = setup({ db });
  const response = await handleRequest(request(), ctx.env, ctx.dependencies);
  assert.deepEqual(await response.json(), { status: 'rejected' });
  assert.equal(ctx.calls, 0);
});

test('public endpoint does not reveal raw purchase tokens', async () => {
  const ctx = setup({ googleStatus: 503 });
  const response = await handleRequest(request(), ctx.env, ctx.dependencies);
  assert.equal((await response.text()).includes(TOKEN), false);
});

test('rejects unknown paths and non-POST requests', async () => {
  const ctx = setup();
  const other = await handleRequest(
    new Request('https://verify.example.com/other'),
    ctx.env, ctx.dependencies,
  );
  const wrongMethod = await handleRequest(
    new Request('https://verify.example.com/verify'),
    ctx.env, ctx.dependencies,
  );
  assert.equal(other.status, 404);
  assert.equal(wrongMethod.status, 405);
});

test('cron stores only hashes and refreshes revocation freshness', async () => {
  const db = new FakeD1({ fresh: false });
  const result = await runScheduledSync(
    { ENTITLEMENTS_DB: db },
    {
      now: () => NOW,
      getAccessToken: async () => 'test-only-access-token',
      fetchImpl: async (url) => {
        assert.match(String(url), /voidedpurchases/);
        return new Response(JSON.stringify({
          voidedPurchases: [
            {
              purchaseToken: TOKEN,
              voidedTimeMillis: String(NOW - 120000),
            },
          ],
        }), { status: 200 });
      },
    },
  );
  assert.equal(result, 1);
  assert.equal(db.completedAt, NOW);
  assert.equal(db.revoked.size, 1);
  assert.equal(db.revoked.has(TOKEN), false);
  assert.equal(db.revoked.has(await tokenHash(TOKEN)), true);
  const ctx = setup({ db });
  const response = await handleRequest(request(), ctx.env, ctx.dependencies);
  assert.deepEqual(await response.json(), { status: 'rejected' });
  assert.equal(ctx.calls, 0);
});

test('failed cron never makes the ledger appear up-to-date', async () => {
  const db = new FakeD1({ fresh: false });
  await assert.rejects(
    runScheduledSync(
      { ENTITLEMENTS_DB: db },
      {
        now: () => NOW,
        getAccessToken: async () => 'test-only-access-token',
        fetchImpl: async () => new Response('error', { status: 503 }),
      },
    ),
  );
  assert.equal(db.completedAt, null);
});

test('cron follows all voided purchase pages before updating freshness', async () => {
  const db = new FakeD1({ fresh: false });
  let pages = 0;
  const result = await runScheduledSync(
    { ENTITLEMENTS_DB: db },
    {
      now: () => NOW,
      getAccessToken: async () => 'test-only-access-token',
      fetchImpl: async (url) => {
        pages++;
        const pageToken = new URL(url).searchParams.get('token');
        if (!pageToken) {
          return new Response(JSON.stringify({
            tokenPagination: { nextPageToken: 'second-page' },
            voidedPurchases: [{ purchaseToken: 'first-token', voidedTimeMillis: String(NOW - 1000) }],
          }), { status: 200 });
        }
        assert.equal(pageToken, 'second-page');
        return new Response(JSON.stringify({
          voidedPurchases: [{ purchaseToken: 'second-token', voidedTimeMillis: String(NOW - 2000) }],
        }), { status: 200 });
      },
    },
  );
  assert.equal(result, 2);
  assert.equal(pages, 2);
  assert.equal(db.revoked.size, 2);
  assert.equal(db.completedAt, NOW);
});

test('partial cron failure leaves sync timestamp unchanged', async () => {
  const db = new FakeD1({ fresh: false });
  let pages = 0;
  await assert.rejects(
    runScheduledSync(
      { ENTITLEMENTS_DB: db },
      {
        now: () => NOW,
        getAccessToken: async () => 'test-only-access-token',
        fetchImpl: async () => {
          pages++;
          if (pages === 1) {
            return new Response(JSON.stringify({
              tokenPagination: { nextPageToken: 'next' },
              voidedPurchases: [{ purchaseToken: TOKEN }],
            }), { status: 200 });
          }
          return new Response('Temporary failure', { status: 503 });
        },
      },
    ),
  );
  assert.equal(pages, 2);
  assert.equal(db.completedAt, null);
  // The partial revocation write is safe; the next successful scan is idempotent.
  assert.equal(db.revoked.size, 1);
});
