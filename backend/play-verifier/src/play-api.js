export const PACKAGE_NAME = 'com.tjsongwei.tts_text_mp3_mobile';
export const PRODUCT_ID = 'remove_ads';
const API_BASE = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications';

export function classifyPurchase(purchase) {
  if (
    !purchase ||
    purchase.purchaseStateContext?.purchaseState !== 'PURCHASED'
  ) {
    return 'rejected';
  }
  if (!Array.isArray(purchase.productLineItem)) return 'rejected';
  const line = purchase.productLineItem.find((item) =>
    item?.productId === PRODUCT_ID,
  );
  if (!line) return 'rejected';
  if (line.productOfferDetails?.consumptionState === 'CONSUMPTION_STATE_CONSUMED') {
    return 'rejected';
  }
  // The Play API documents refundableQuantity for partial/full refunds.
  // Do not grant an item that has no refundable units left.
  if (line.productOfferDetails?.refundableQuantity === 0) {
    return 'rejected';
  }
  if (line.productOfferDetails?.rentOfferDetails) {
    return 'rejected';
  }
  return 'verified';
}

export async function lookupGooglePurchase(purchaseToken, accessToken, {
  fetchImpl = fetch,
} = {}) {
  const url =
    `${API_BASE}/${PACKAGE_NAME}/purchases/productsv2/tokens/` +
    encodeURIComponent(purchaseToken);
  const response = await fetchImpl(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
    signal: AbortSignal.timeout(10000),
  });

  if ([400, 404, 410].includes(response.status)) return 'rejected';
  if (!response.ok) throw new Error('Google Play purchase verification unavailable.');

  let purchase;
  try {
    purchase = await response.json();
  } catch {
    throw new Error('Google Play purchase response invalid.');
  }
  return classifyPurchase(purchase);
}

export async function listVoidedPurchases(accessToken, {
  startTime,
  endTime,
  pageToken,
  fetchImpl = fetch,
} = {}) {
  const url = new URL(
    `${API_BASE}/${PACKAGE_NAME}/purchases/voidedpurchases`,
  );
  url.searchParams.set('type', '0'); // Only one-time products.
  url.searchParams.set('startTime', String(startTime));
  url.searchParams.set('endTime', String(endTime));
  url.searchParams.set('includeQuantityBasedPartialRefund', 'true');
  if (pageToken) url.searchParams.set('token', pageToken);

  const response = await fetchImpl(url.toString(), {
    headers: { Authorization: `Bearer ${accessToken}` },
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error('Voided purchases sync failed.');

  let body;
  try {
    body = await response.json();
  } catch {
    throw new Error('Voided purchases response invalid.');
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new Error('Voided purchases response invalid.');
  }
  const voided = body.voidedPurchases ?? [];
  if (!Array.isArray(voided)) {
    throw new Error('Voided purchases records invalid.');
  }
  return {
    voided,
    nextPageToken: typeof body.tokenPagination?.nextPageToken === 'string'
      ? body.tokenPagination.nextPageToken
      : typeof body.nextPageToken === 'string'
        ? body.nextPageToken
        : null,
  };
}
