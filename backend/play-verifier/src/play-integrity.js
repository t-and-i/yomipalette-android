import { PACKAGE_NAME } from './play-api.js';
import { tokenHash } from './revocations.js';

export const INTEGRITY_SCOPE = 'https://www.googleapis.com/auth/playintegrity';
const MAX_VERDICT_AGE_MS = 2 * 60_000;
const CLOCK_SKEW_MS = 30_000;

export async function verifyPlayIntegrity(payload, purchaseTokenHash, accessToken, {
  fetchImpl,
  now,
}) {
  // Keep this ordered, versioned array in sync with the Flutter verifier.
  const expectedHash = await tokenHash(JSON.stringify([
    'yomipalette:/verify:v1',
    payload.packageName,
    payload.productId,
    purchaseTokenHash,
    payload.requestId,
  ]));
  const response = await fetchImpl(
    'https://playintegrity.googleapis.com/v1/' + PACKAGE_NAME + ':decodeIntegrityToken',
    {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + accessToken,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ integrity_token: payload.integrityToken }),
      signal: AbortSignal.timeout(5000),
    },
  );
  if (!response.ok) return false;

  const { tokenPayloadExternal: verdict } = await response.json();
  const details = verdict?.requestDetails;
  if (details?.requestPackageName !== PACKAGE_NAME || details.requestHash !== expectedHash) {
    return false;
  }
  const timestamp = details.timestampMillis;
  if (typeof timestamp !== 'string' || !/^[0-9]{13}$/.test(timestamp)) return false;
  const age = now() - Number(timestamp);
  if (age < -CLOCK_SKEW_MS || age > MAX_VERDICT_AGE_MS) return false;

  const app = verdict.appIntegrity;
  const deviceLabels = verdict.deviceIntegrity?.deviceRecognitionVerdict;
  return app?.appRecognitionVerdict === 'PLAY_RECOGNIZED' &&
    app.packageName === PACKAGE_NAME &&
    verdict.accountDetails?.appLicensingVerdict === 'LICENSED' &&
    Array.isArray(deviceLabels) &&
    deviceLabels.includes('MEETS_DEVICE_INTEGRITY');
}
