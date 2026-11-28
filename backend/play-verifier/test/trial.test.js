import assert from 'node:assert/strict';
import test from 'node:test';
import { handleRequest } from '../src/worker.js';
import { verifyGoogleIdToken } from '../src/google-id-token.js';
import { subjectDigest, getOrStartTrial } from '../src/trial.js';
import { PACKAGE_NAME } from '../src/play-api.js';
import { tokenHash } from '../src/revocations.js';
import { TRIAL_SECONDS } from '../src/trial-grants.js';

const NOW = Date.parse('2026-11-23T00:00:00.000Z');
const CLIENT_ID = 'test-client.apps.googleusercontent.com';
const DEVICE = 'a'.repeat(43);
const HMAC_KEY = Buffer.alloc(32, 23).toString('base64url');

function b64(input) { return Buffer.from(JSON.stringify(input)).toString('base64url'); }
class TrialDb {
  records = new Map();
  prepare(sql) {
    return { bind: (...args) => ({
      run: async () => {
        if (sql.startsWith('INSERT OR IGNORE')) {
          if (!this.records.has(args[0])) this.records.set(args[0], {
            started_at_ms: args[1], expires_at_ms: args[2],
            last_verified_at_ms: args[3], status: 'active',
          });
        } else if (sql.startsWith('UPDATE trial_entitlements')) {
          this.records.get(args[1]).last_verified_at_ms = args[0];
        } else throw Error('Unexpected D1 write');
        return { success: true };
      },
      first: async () => {
        if (!sql.startsWith('SELECT started_at_ms')) throw Error('Unexpected D1 read');
        return this.records.get(args[0]) ?? null;
      },
    }) };
  }
}

let scenarioCounter = 0;
async function scenario() {
  const kid = 'trial-test-rsa-' + (++scenarioCounter);
  const rsa = await crypto.subtle.generateKey({
    name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256',
  }, true, ['sign', 'verify']);
  const ed = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  const publicRsa = await crypto.subtle.exportKey('jwk', rsa.publicKey);
  const edPkcs8 = await crypto.subtle.exportKey('pkcs8', ed.privateKey);
  const env = {
    GOOGLE_SIGN_IN_WEB_CLIENT_ID: CLIENT_ID,
    TRIAL_SUBJECT_HMAC_KEY: HMAC_KEY,
    OFFLINE_GRANT_KEY_ID: 'trial-test-key',
    OFFLINE_GRANT_PRIVATE_KEY_PKCS8: Buffer.from(edPkcs8).toString('base64'),
    ENTITLEMENTS_DB: new TrialDb(),
    VERIFY_IP_RATE_LIMIT: { limit: async () => ({ success: true }) },
    VERIFY_TOKEN_RATE_LIMIT: { limit: async () => ({ success: true }) },
  };
  async function idToken(at = NOW, sub = '123456789') {
    const header = b64({ alg: 'RS256', typ: 'JWT', kid });
    const payload = b64({
      iss: 'https://accounts.google.com',
      aud: CLIENT_ID, sub,
      iat: Math.floor(at / 1000) - 30, exp: Math.floor(at / 1000) + 3600,
    });
    const signed = header + '.' + payload;
    const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', rsa.privateKey,
      new TextEncoder().encode(signed));
    return signed + '.' + Buffer.from(sig).toString('base64url');
  }
  async function perform({
    at = NOW, sub = '123456789', deviceId = DEVICE, requestId = 'c'.repeat(32),
    mutateRequest, mutateVerdict,
  } = {}) {
    const googleIdToken = await idToken(at, sub);
    const payload = {
      packageName: PACKAGE_NAME, deviceId, googleIdToken,
      requestId, integrityToken: 'fake-integrity-token',
    };
    const incoming = mutateRequest ? mutateRequest(payload) : payload;
    const request = new Request('https://example.test/trial', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(incoming),
    });
    return handleRequest(request, env, {
      now: () => at,
      getAccessToken: async () => 'fake-access-token',
      fetchImpl: async url => {
        if (String(url).endsWith('/certs')) {
          return Response.json({ keys: [{ ...publicRsa, kid, alg: 'RS256' }] });
        }
        assert.match(String(url), /:decodeIntegrityToken$/);
        const hash = await tokenHash(JSON.stringify([
          'yomipalette:/trial:v1', PACKAGE_NAME, await tokenHash(googleIdToken),
          requestId, deviceId,
        ]));
        const verdict = {
          requestDetails: {
            requestPackageName: PACKAGE_NAME,
            requestHash: hash, timestampMillis: String(at),
          },
          appIntegrity: {
            appRecognitionVerdict: 'PLAY_RECOGNIZED', packageName: PACKAGE_NAME,
          },
          accountDetails: { appLicensingVerdict: 'LICENSED' },
          deviceIntegrity: { deviceRecognitionVerdict: ['MEETS_DEVICE_INTEGRITY'] },
        };
        return Response.json({ tokenPayloadExternal: mutateVerdict
          ? mutateVerdict(verdict) : verdict });
      },
    });
  }
  return { env, perform, idToken, publicRsa, ed, kid };
}

test('account starts one immutable 30-day trial; reinstall cannot reset it', async () => {
  const ctx = await scenario();
  const first = await ctx.perform();
  assert.equal(first.status, 200);
  const one = await first.json();
  assert.equal(one.status, 'active');
  assert.ok(one.offlineGrant);
  assert.equal(ctx.env.ENTITLEMENTS_DB.records.size, 1);
  const row = [...ctx.env.ENTITLEMENTS_DB.records.values()][0];
  const started = row.started_at_ms;
  const second = await ctx.perform({ at: NOW + 12 * 24 * 3600_000, deviceId: 'b'.repeat(43) });
  assert.equal((await second.json()).status, 'active');
  assert.equal(row.started_at_ms, started);
  assert.equal(row.expires_at_ms, started + 30 * 86400_000);
  const expired = await ctx.perform({ at: NOW + 30 * 86400_000 });
  assert.deepEqual(await expired.json(), { status: 'expired' });
  assert.equal(row.started_at_ms, started);
});

test('trial grant has separate purpose, verified 72h cap and 30d hard limit', async () => {
  const ctx = await scenario();
  const initial = await (await ctx.perform()).json();
  const [payload, signature] = initial.offlineGrant.split('.');
  const parsed = JSON.parse(Buffer.from(payload, 'base64url').toString());
  assert.equal(parsed.v, 2);
  assert.equal(parsed.kind, 'trial');
  assert.equal(parsed.deviceId, DEVICE);
  assert.equal(parsed.exp - parsed.iat, 72 * 3600);
  assert.equal(parsed.trialExpiresAt - parsed.trialStartedAt, TRIAL_SECONDS);
  assert.equal(await crypto.subtle.verify('Ed25519', ctx.ed.publicKey,
    Buffer.from(signature, 'base64url'), Buffer.from(payload, 'base64url')), true);
  const almostExpired = await (await ctx.perform({
    at: NOW + 29 * 86400_000,
  })).json();
  const closing = JSON.parse(Buffer.from(almostExpired.offlineGrant.split('.')[0], 'base64url'));
  assert.equal(closing.exp, closing.trialExpiresAt);
  assert.equal(closing.exp - closing.iat, 86400);
});

test('Google ID token signature, audience and timing are checked', async () => {
  const ctx = await scenario();
  const token = await ctx.idToken();
  const loadKey = async () => ({ ...ctx.publicRsa, kid: ctx.kid });
  assert.equal(await verifyGoogleIdToken(token, CLIENT_ID, {
    now: () => NOW, loadKey,
  }), '123456789');
  assert.equal(await verifyGoogleIdToken(token, 'wrong-client', {
    now: () => NOW, loadKey,
  }), null);
  assert.equal(await verifyGoogleIdToken(token, CLIENT_ID, {
    now: () => NOW + 3700_000, loadKey,
  }), null);
  assert.equal(await verifyGoogleIdToken(token.slice(0, -4) + 'abcd', CLIENT_ID, {
    now: () => NOW, loadKey,
  }), null);
});

test('forged account or integrity verdict never creates trial', async () => {
  const ctx = await scenario();
  const wrong = await ctx.perform({
    mutateRequest: p => ({ ...p, googleIdToken: 'not-google-token' }),
  });
  assert.equal(wrong.status, 400);
  const forgedHash = await ctx.perform({
    mutateVerdict: v => ({
      ...v, requestDetails: { ...v.requestDetails, requestHash: '0'.repeat(64) },
    }),
  });
  assert.equal(forgedHash.status, 503);
  const badDevice = await ctx.perform({
    mutateVerdict: v => ({
      ...v, deviceIntegrity: { deviceRecognitionVerdict: [] },
    }),
  });
  assert.equal(badDevice.status, 503);
  assert.equal(ctx.env.ENTITLEMENTS_DB.records.size, 0);
});

test('D1 starting timestamp is atomic and blocked users cannot restart', async () => {
  const ctx = await scenario();
  const key = await subjectDigest('123456789', HMAC_KEY);
  const records = await Promise.all([
    getOrStartTrial(ctx.env.ENTITLEMENTS_DB, key, NOW),
    getOrStartTrial(ctx.env.ENTITLEMENTS_DB, key, NOW + 500),
  ]);
  assert.equal(records[0].startedAtMs, NOW);
  assert.equal(records[1].startedAtMs, NOW);
  ctx.env.ENTITLEMENTS_DB.records.get(key).status = 'blocked';
  const status = await (await ctx.perform()).json();
  assert.deepEqual(status, { status: 'blocked' });
});


test('missing signing key blocks trial before inserting first-use record', async () => {
  const ctx = await scenario();
  delete ctx.env.OFFLINE_GRANT_PRIVATE_KEY_PKCS8;
  const response = await ctx.perform();
  assert.equal(response.status, 503);
  assert.equal(ctx.env.ENTITLEMENTS_DB.records.size, 0);
});
