import { getPlayAccessToken } from './oauth.js';
import { lookupGooglePurchase, PACKAGE_NAME, PRODUCT_ID } from './play-api.js';
import { verifyPubSubToken } from './pubsub-auth.js';
import { recordRevocation } from './revocations.js';

const MAX_BYTES = 32768;

function result(status) {
  return new Response(null, { status, headers: {
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  } });
}

async function readEnvelope(request) {
  if (!request.headers.get('content-type')?.toLowerCase().includes('application/json')) {
    return null;
  }
  if (Number(request.headers.get('content-length') ?? 0) > MAX_BYTES || !request.body) {
    return null;
  }
  const reader = request.body.getReader();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let total = 0;
  let body = '';
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_BYTES) return null;
      body += decoder.decode(value, { stream: true });
    }
    body += decoder.decode();
    const envelope = JSON.parse(body);
    return envelope && typeof envelope === 'object' && !Array.isArray(envelope)
      ? envelope
      : null;
  } catch {
    return null;
  } finally {
    reader.releaseLock();
  }
}

function unpackNotification(envelope) {
  if (typeof envelope?.message?.data !== 'string' ||
      envelope.message.data.length > MAX_BYTES || envelope.message.data.length === 0) {
    return null;
  }
  try {
    const binary = atob(envelope.message.data);
    const bytes = Uint8Array.from(binary, (ch) => ch.charCodeAt(0));
    const value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    return value && typeof value === 'object' && !Array.isArray(value)
      ? value
      : null;
  } catch {
    return null;
  }
}

function validToken(token) {
  return typeof token === 'string' && token.length >= 8 && token.length <= 4096;
}

/**
 * Google Pub/Sub authenticated push receiver. Does not expose raw purchase
 * tokens or credentials in its HTTP responses, logs, or persisted data.
 *
 * Failures returning 503 intentionally cause Pub/Sub redelivery.
 */
export async function handleRtdn(request, env, {
  now = Date.now,
  fetchImpl = fetch,
  getAccessToken = getPlayAccessToken,
  verifyToken = verifyPubSubToken,
  lookup = lookupGooglePurchase,
} = {}) {
  if (request.method !== 'POST') return result(405);
  if (!env?.RTDN_OIDC_AUDIENCE ||
      !env?.RTDN_PUSH_SERVICE_ACCOUNT_EMAIL ||
      !env?.RTDN_PUBSUB_SUBSCRIPTION) return result(503);

  let authenticated;
  try {
    authenticated = await verifyToken(request.headers.get('authorization'), {
      audience: env.RTDN_OIDC_AUDIENCE,
      serviceAccountEmail: env.RTDN_PUSH_SERVICE_ACCOUNT_EMAIL,
      fetchImpl,
      now,
    });
  } catch {
    return result(503); // Public signing certificates could not be fetched.
  }
  if (!authenticated) return result(401);

  const envelope = await readEnvelope(request);
  if (!envelope || envelope.subscription !== env.RTDN_PUBSUB_SUBSCRIPTION) {
    return result(400);
  }
  const payload = unpackNotification(envelope);
  if (!payload) return result(400);
  if (payload.packageName !== PACKAGE_NAME) return result(204);

  // A notification is only a signal, never by itself a reason to grant access.
  if (payload.testNotification || payload.oneTimeProductNotification?.notificationType === 1) {
    return result(204);
  }

  const oneTime = payload.oneTimeProductNotification;
  const voided = payload.voidedPurchaseNotification;
  const isCanceled = oneTime?.notificationType === 2 && oneTime.sku === PRODUCT_ID;
  const isVoided = voided?.productType === 2 &&
    (voided?.refundType === 1 || voided?.refundType === 2);
  if (!isCanceled && !isVoided) return result(204);
  const purchaseToken = isCanceled ? oneTime.purchaseToken : voided.purchaseToken;
  if (!validToken(purchaseToken)) return result(400);

  try {
    // Full revocation is authoritative. For a cancellation or partial refund,
    // fetch current purchase state to avoid revoking a still-valid purchase.
    let shouldRevoke = isVoided && voided.refundType === 1;
    if (!shouldRevoke) {
      const accessToken = await getAccessToken(env, { now, fetchImpl });
      const state = await lookup(purchaseToken, accessToken, { fetchImpl });
      shouldRevoke = state === 'rejected';
      if (!shouldRevoke && state !== 'verified') return result(503);
    }
    if (shouldRevoke) {
      const eventMs = Number(payload.eventTimeMillis);
      await recordRevocation(
        env.ENTITLEMENTS_DB,
        purchaseToken,
        Number.isFinite(eventMs) && eventMs >= 0 ? eventMs : now(),
      );
    }
    // Do not update sync_state: RTDN cannot replace a full Voided Purchases scan.
    return result(204);
  } catch {
    return result(503);
  }
}
