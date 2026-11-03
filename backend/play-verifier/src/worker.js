import { getPlayAccessToken } from './oauth.js';
import {
  PACKAGE_NAME,
  PRODUCT_ID,
  lookupGooglePurchase,
} from './play-api.js';
import {
  checkRevocation,
  syncVoidedPurchases,
  tokenHash,
} from './revocations.js';

const MAX_REQUEST_BYTES = 8192;

function json(status, value) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store, private',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}

async function readBoundedJson(request) {
  if (!request.headers.get('content-type')?.toLowerCase().includes('application/json')) {
    return null;
  }
  const declaredLength = Number(request.headers.get('content-length') ?? 0);
  if (declaredLength > MAX_REQUEST_BYTES) return null;

  if (!request.body) return null;
  const reader = request.body.getReader();
  const decoder = new TextDecoder();
  let total = 0;
  let text = '';
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_REQUEST_BYTES) return null;
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
    const body = JSON.parse(text);
    return body && typeof body === 'object' && !Array.isArray(body)
      ? body
      : null;
  } catch {
    return null;
  } finally {
    reader.releaseLock();
  }
}

function validPayload(body) {
  return body &&
    body.packageName === PACKAGE_NAME &&
    body.productId === PRODUCT_ID &&
    typeof body.purchaseToken === 'string' &&
    body.purchaseToken.length >= 8 &&
    body.purchaseToken.length <= 4096;
}

/**
 * Public purchase verification endpoint for the Flutter app.
 *
 * This is a pre-deployment foundation. Deployment must remain blocked until
 * Google Play service-account grants, D1 freshness, abuse prevention and
 * purchase-token replay protections have all been evaluated.
 */
export async function handleRequest(request, env, {
  now = Date.now,
  fetchImpl = fetch,
  getAccessToken = getPlayAccessToken,
} = {}) {
  const url = new URL(request.url);
  if (url.pathname !== '/verify') return json(404, { error: 'not_found' });
  if (request.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  const payload = await readBoundedJson(request);
  if (!validPayload(payload)) {
    return json(400, { error: 'invalid_purchase_request' });
  }

  try {
    const hash = await tokenHash(payload.purchaseToken);
    const revoked = await checkRevocation(env.ENTITLEMENTS_DB, hash, now());
    if (revoked) return json(200, { status: 'rejected' });

    const accessToken = await getAccessToken(env, { fetchImpl, now });
    const status = await lookupGooglePurchase(
      payload.purchaseToken,
      accessToken,
      { fetchImpl },
    );
    return json(200, { status });
  } catch {
    // No token, credential, raw Google error or request body in responses/logs.
    return json(503, { status: 'unavailable' });
  }
}

/** Synchronize Google Play refunds/revocations every six hours. */
export async function runScheduledSync(env, {
  now = Date.now,
  fetchImpl = fetch,
  getAccessToken = getPlayAccessToken,
} = {}) {
  const accessToken = await getAccessToken(env, { now, fetchImpl });
  return syncVoidedPurchases(env.ENTITLEMENTS_DB, accessToken, {
    now,
    fetchImpl,
  });
}

export default {
  fetch: handleRequest,
  async scheduled(_event, env) {
    await runScheduledSync(env);
  },
};
