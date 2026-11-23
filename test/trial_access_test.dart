import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_text_mp3_mobile/services/signed_trial_cache.dart';
import 'package:tts_text_mp3_mobile/services/trial_access.dart';
import 'package:tts_text_mp3_mobile/services/trial_verifier.dart';

final _algorithm = Ed25519();
final _start = DateTime.utc(2026, 11, 23, 1);
final _deviceId = 'T' * 43;

String _encode(List<int> b) => base64Url.encode(b).replaceAll('=', '');

class _Identity implements TrialIdentityProvider {
  String? token = 'mock-google-id-token';
  int signIns = 0;
  int silentAttempts = 0;
  @override
  Future<String?> signIn() async {
    signIns++;
    return token;
  }

  @override
  Future<String?> signInSilently() async {
    silentAttempts++;
    return token;
  }

  @override
  Future<void> signOut() async {
    token = null;
  }
}

class _Verifier implements TrialVerifier {
  _Verifier(this.keys, this.clock) : startedAt = _start;
  final KeyPair keys;
  final DateTime Function() clock;
  final DateTime startedAt;
  TrialVerificationStatus? forced;
  int calls = 0;

  @override
  Future<TrialVerificationOutcome> verify({
    required String idToken,
    required String deviceId,
  }) async {
    calls++;
    final now = clock().toUtc();
    final ends = startedAt.add(const Duration(days: 30));
    final status =
        forced ??
        (now.isBefore(ends)
            ? TrialVerificationStatus.active
            : TrialVerificationStatus.expired);
    if (status != TrialVerificationStatus.active) {
      return TrialVerificationOutcome(status);
    }
    final grantEnd = now.add(const Duration(hours: 72)).isBefore(ends)
        ? now.add(const Duration(hours: 72))
        : ends;
    final claims = {
      'v': 2,
      'kind': 'trial',
      'kid': 'test-trial-key',
      'pkg': 'com.tjsongwei.tts_text_mp3_mobile',
      'deviceId': deviceId,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': grantEnd.millisecondsSinceEpoch ~/ 1000,
      'trialStartedAt': startedAt.millisecondsSinceEpoch ~/ 1000,
      'trialExpiresAt': ends.millisecondsSinceEpoch ~/ 1000,
    };
    final bytes = utf8.encode(jsonEncode(claims));
    final signature = await _algorithm.sign(bytes, keyPair: keys);
    return TrialVerificationOutcome(
      status,
      grant: '${_encode(bytes)}.${_encode(signature.bytes)}',
    );
  }

  @override
  void dispose() {}
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'Google account is required; local installation never starts a trial',
    () async {
      var now = _start;
      final keys = await _algorithm.newKeyPair();
      final pub = _encode((await keys.extractPublicKey()).bytes);
      SignedTrialEntitlementStore cache() => SignedTrialEntitlementStore(
        deviceIdProvider: () async => _deviceId,
        publicKeyBase64: pub,
        keyId: 'test-trial-key',
        clock: () => now,
      );
      final identity = _Identity();
      final verifier = _Verifier(keys, () => now);
      final controller = TrialAccessController(
        store: cache(),
        identity: identity,
        verifier: verifier,
        allowQaTrial: false,
        clock: () => now,
      );
      await controller.initialize();
      expect(controller.isActive, false);
      expect(controller.startedAt, null);
      expect(identity.signIns, 0);
      await controller.signIn();
      expect(identity.signIns, 1);
      expect(verifier.calls, 1);
      expect(controller.isActive, true);
      expect(controller.daysRemaining, 30);
      controller.dispose();
    },
  );

  test(
    'signed offline trial expires at 72h and cannot be extended locally',
    () async {
      var now = _start;
      final keys = await _algorithm.newKeyPair();
      final pub = _encode((await keys.extractPublicKey()).bytes);
      SignedTrialEntitlementStore makeStore() => SignedTrialEntitlementStore(
        deviceIdProvider: () async => _deviceId,
        publicKeyBase64: pub,
        keyId: 'test-trial-key',
        clock: () => now,
      );
      final identity = _Identity();
      final verifier = _Verifier(keys, () => now);
      final controller = TrialAccessController(
        store: makeStore(),
        identity: identity,
        verifier: verifier,
        allowQaTrial: false,
        clock: () => now,
      );
      await controller.initialize();
      await controller.signIn();
      now = _start.add(const Duration(hours: 71, minutes: 59, seconds: 59));
      final restoredStore = makeStore();
      await restoredStore.initialize();
      expect(restoredStore.hasValidGrant, true);
      now = _start.add(const Duration(hours: 72));
      expect(restoredStore.hasValidGrant, false);
      identity.token = null; // Network/Google login unavailable.
      await controller.refresh();
      expect(controller.isActive, false);
      expect(verifier.calls, 1); // No renewal without a new Google identity.
      controller.dispose();
    },
  );

  test('online renewal does not reset 30-day first-use expiry', () async {
    var now = _start;
    final keys = await _algorithm.newKeyPair();
    final pub = _encode((await keys.extractPublicKey()).bytes);
    SignedTrialEntitlementStore store() => SignedTrialEntitlementStore(
      deviceIdProvider: () async => _deviceId,
      publicKeyBase64: pub,
      keyId: 'test-trial-key',
      clock: () => now,
    );
    final identity = _Identity();
    final verifier = _Verifier(keys, () => now);
    final c = TrialAccessController(
      store: store(),
      identity: identity,
      verifier: verifier,
      allowQaTrial: false,
      clock: () => now,
    );
    await c.initialize();
    await c.signIn();
    now = _start.add(const Duration(days: 29));
    await c.refresh();
    expect(verifier.calls, 2);
    expect(c.daysRemaining, 1);
    now = _start.add(const Duration(days: 30));
    expect(c.isActive, false);
    expect(c.isExpired, true);
    await c.refresh();
    expect(c.isActive, false);
    c.dispose();
  });

  test(
    'permanent purchase grant is never accepted as trial entitlement',
    () async {
      final keys = await _algorithm.newKeyPair();
      final pub = _encode((await keys.extractPublicKey()).bytes);
      final store = SignedTrialEntitlementStore(
        deviceIdProvider: () async => _deviceId,
        publicKeyBase64: pub,
        keyId: 'test-trial-key',
        clock: () => _start,
      );
      await store.initialize();
      final invalid = utf8.encode(
        jsonEncode({
          'v': 1,
          'kind': 'purchase',
          'kid': 'test-trial-key',
          'pkg': 'com.tjsongwei.tts_text_mp3_mobile',
          'productId': 'full_access',
          'deviceId': _deviceId,
          'iat': _start.millisecondsSinceEpoch ~/ 1000,
          'exp':
              _start.add(const Duration(hours: 72)).millisecondsSinceEpoch ~/
              1000,
        }),
      );
      final signed = await _algorithm.sign(invalid, keyPair: keys);
      expect(
        await store.accept('${_encode(invalid)}.${_encode(signed.bytes)}'),
        false,
      );
    },
  );
}
