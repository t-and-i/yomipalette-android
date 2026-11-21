import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_text_mp3_mobile/services/ad_free_purchase.dart';
import 'package:tts_text_mp3_mobile/services/offline_entitlement_cache.dart';
import 'package:tts_text_mp3_mobile/services/purchase_verifier.dart';

final _algorithm = Ed25519();
final _referenceTime = DateTime.utc(2026, 11, 21, 12);

String _encode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Future<String> _sign({
  required KeyPair keyPair,
  required String deviceId,
  required DateTime issued,
  String productId = 'full_access',
  String packageId = billingPackageName,
  int hours = 72,
  String receiptToken = 'valid-receipt-token-12345',
}) async {
  final payload = utf8.encode(
    jsonEncode({
      'v': 1,
      'kid': 'test-key-1',
      'pkg': packageId,
      'productId': productId,
      'deviceId': deviceId,
      'receiptHash': hashes.sha256
          .convert(utf8.encode(receiptToken))
          .toString(),
      'iat': issued.millisecondsSinceEpoch ~/ 1000,
      'exp': issued.add(Duration(hours: hours)).millisecondsSinceEpoch ~/ 1000,
    }),
  );
  final signature = await _algorithm.sign(payload, keyPair: keyPair);
  return '${_encode(payload)}.${_encode(signature.bytes)}';
}

class _FakeBilling implements AdFreeBillingGateway {
  final events = StreamController<List<PurchaseDetails>>.broadcast(sync: true);
  bool online = true;
  int restores = 0;

  @override
  Stream<List<PurchaseDetails>> get purchases => events.stream;
  @override
  Future<bool> isAvailable() async => online;
  @override
  Future<ProductDetailsResponse> queryProducts(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: [
          ProductDetails(
            id: 'full_access',
            title: 'Full access',
            description: '',
            price: '¥500',
            rawPrice: 500,
            currencyCode: 'JPY',
          ),
        ],
        notFoundIDs: [],
      );
  @override
  Future<bool> purchase(ProductDetails product) async => true;
  @override
  Future<void> restore() async {
    restores++;
  }

  @override
  Future<void> complete(PurchaseDetails details) async {}
}

PurchaseDetails _receipt({String productId = 'full_access'}) => PurchaseDetails(
  productID: productId,
  purchaseID: 'test-order',
  verificationData: PurchaseVerificationData(
    localVerificationData: '',
    serverVerificationData: 'fake-google-play-receipt-token',
    source: 'google_play',
  ),
  transactionDate: '1',
  status: PurchaseStatus.purchased,
);

class _FakeSignerVerifier
    implements PurchaseVerifier, OfflineGrantPurchaseVerifier {
  _FakeSignerVerifier(this.keyPair, this.clock);
  final KeyPair keyPair;
  final DateTime Function() clock;
  PurchaseVerificationResult current = PurchaseVerificationResult.verified;
  bool issueGrant = true;
  int calls = 0;

  @override
  Future<PurchaseVerificationOutcome> verifyForDevice(
    PurchaseDetails purchase,
    String deviceId,
  ) async {
    calls++;
    if (current != PurchaseVerificationResult.verified) {
      return PurchaseVerificationOutcome(current);
    }
    return PurchaseVerificationOutcome(
      current,
      offlineGrant: issueGrant
          ? await _sign(
              keyPair: keyPair,
              deviceId: deviceId,
              issued: clock(),
              productId: purchase.productID,
              receiptToken: purchase.verificationData.serverVerificationData,
            )
          : null,
    );
  }

  @override
  Future<PurchaseVerificationResult> verify(PurchaseDetails purchase) async =>
      current;

  @override
  void dispose() {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'signed grant survives restart/offline and expires after exactly 72 hours',
    () async {
      var now = _referenceTime;
      final keys = await _algorithm.newKeyPair();
      final publicKey = await keys.extractPublicKey();
      final key = _encode(publicKey.bytes);
      final cache = SignedOfflineEntitlementStore(
        publicKeyBase64: key,
        keyId: 'test-key-1',
        clock: () => now,
      );
      await cache.initialize();
      final device = await cache.getDeviceId();
      final grant = await _sign(keyPair: keys, deviceId: device, issued: now);
      expect(await cache.accept(grant), true);
      await expectLater(
        cache.rememberPurchase('full_access', 'different-receipt-token'),
        throwsArgumentError,
      );
      await cache.rememberPurchase('full_access', 'valid-receipt-token-12345');
      expect(cache.hasValidGrant, true);
      expect(
        (await cache.getCachedPurchase())?.token,
        'valid-receipt-token-12345',
      );

      now = now.add(const Duration(hours: 71));
      final restarted = SignedOfflineEntitlementStore(
        publicKeyBase64: key,
        keyId: 'test-key-1',
        clock: () => now,
      );
      await restarted.initialize();
      expect(restarted.hasValidGrant, true);
      expect(await restarted.getDeviceId(), device);

      now = _referenceTime.add(const Duration(hours: 72));
      expect(restarted.hasValidGrant, false);
      // Retain the encrypted receipt for the next online re-validation.
      expect((await restarted.getCachedPurchase())?.productId, 'full_access');
      await restarted.refresh();
      expect(restarted.hasValidGrant, false);
    },
  );

  test('tampering, different signing key, device, product and clock rollback fail closed', () async {
    var now = _referenceTime;
    final keys = await _algorithm.newKeyPair();
    final wrongKeys = await _algorithm.newKeyPair();
    final publicKey = await keys.extractPublicKey();
    final cache = SignedOfflineEntitlementStore(
      publicKeyBase64: _encode(publicKey.bytes),
      keyId: 'test-key-1',
      clock: () => now,
    );
    await cache.initialize();
    final device = await cache.getDeviceId();
    final grant = await _sign(keyPair: keys, deviceId: device, issued: now);
    expect(await cache.accept(grant), true);
    expect(await cache.accept(grant.replaceFirst('ey', 'ea')), false);
    expect(
      await cache.accept(
        await _sign(keyPair: wrongKeys, deviceId: device, issued: now),
      ),
      false,
    );
    expect(
      await cache.accept(
        await _sign(keyPair: keys, deviceId: 'B' * 43, issued: now),
      ),
      false,
    );
    expect(
      await cache.accept(
        await _sign(
          keyPair: keys,
          deviceId: device,
          issued: now,
          productId: 'other',
        ),
      ),
      false,
    );
    expect(
      await cache.accept(
        await _sign(
          keyPair: keys,
          deviceId: device,
          issued: now,
          packageId: 'fake',
        ),
      ),
      false,
    );
    expect(
      await cache.accept(
        await _sign(keyPair: keys, deviceId: device, issued: now, hours: 73),
      ),
      false,
    );
    expect(cache.hasValidGrant, true);

    now = now.add(const Duration(hours: 3));
    await cache.refresh();
    now = now.subtract(const Duration(hours: 1));
    expect(cache.hasValidGrant, false);
    await cache.refresh();
    expect(cache.hasValidGrant, false);
    now = _referenceTime.add(const Duration(hours: 3));
    await cache.refresh();
    expect(cache.hasValidGrant, true);
  });

  test('copying a signed token to a different installation fails', () async {
    final keys = await _algorithm.newKeyPair();
    final key = _encode((await keys.extractPublicKey()).bytes);
    final original = SignedOfflineEntitlementStore(
      publicKeyBase64: key,
      keyId: 'test-key-1',
      clock: () => _referenceTime,
    );
    await original.initialize();
    final grant = await _sign(
      keyPair: keys,
      deviceId: await original.getDeviceId(),
      issued: _referenceTime,
    );
    FlutterSecureStorage.setMockInitialValues({
      'offline_entitlement_device_v1': 'B' * 43,
      'offline_entitlement_grant_v1': grant,
    });
    final copied = SignedOfflineEntitlementStore(
      publicKeyBase64: key,
      keyId: 'test-key-1',
      clock: () => _referenceTime,
    );
    await copied.initialize();
    expect(copied.hasValidGrant, false);
  });

  test(
    'an online verified status without a signed grant cannot unlock 72 hours',
    () async {
      var now = _referenceTime;
      final keys = await _algorithm.newKeyPair();
      final key = _encode((await keys.extractPublicKey()).bytes);
      final cache = SignedOfflineEntitlementStore(
        publicKeyBase64: key,
        keyId: 'test-key-1',
        clock: () => now,
      );
      final billing = _FakeBilling();
      final verifier = _FakeSignerVerifier(keys, () => now)..issueGrant = false;
      final controller = AdFreePurchaseController(
        gateway: billing,
        verifier: verifier,
        offlineStore: cache,
        clock: () => now,
      );
      await controller.initialize();
      await controller.handleUpdates([_receipt()]);
      expect(controller.isLicensed, true); // Fresh online response only.
      expect(cache.hasValidGrant, false);
      expect(await cache.getCachedPurchase(), null);
      now = now.add(const Duration(minutes: 6));
      // Debug QA deliberately trusts fake Play purchases; production does not.
      // CI runs this suite again with BILLING_QA=false to enforce the limit.
      expect(controller.isLicensed, billingQaMode);
      controller.dispose();
      await billing.events.close();
    },
  );

  test('cache survives unavailable backend but refund revokes cache and stored receipt', () async {
    var now = _referenceTime;
    final keys = await _algorithm.newKeyPair();
    final pub = _encode((await keys.extractPublicKey()).bytes);
    SignedOfflineEntitlementStore cache() => SignedOfflineEntitlementStore(
      publicKeyBase64: pub,
      keyId: 'test-key-1',
      clock: () => now,
    );
    final store = cache();
    final verifier = _FakeSignerVerifier(keys, () => now);
    final billing = _FakeBilling();
    final controller = AdFreePurchaseController(
      gateway: billing,
      verifier: verifier,
      offlineStore: store,
      clock: () => now,
    );
    await controller.initialize();
    await controller.handleUpdates([_receipt()]);
    expect(controller.isLicensed, true);
    expect(store.hasValidGrant, true);
    expect((await store.getCachedPurchase())?.token, isNotEmpty);

    verifier.current = PurchaseVerificationResult.unavailable;
    now = now.add(const Duration(hours: 1));
    await controller.refreshEntitlement();
    expect(controller.isLicensed, true);
    expect(store.hasValidGrant, true);

    verifier.current = PurchaseVerificationResult.rejected;
    await controller.restorePurchases();
    expect(controller.isLicensed, false);
    expect(store.hasValidGrant, false);
    expect(await store.getCachedPurchase(), null);

    controller.dispose();
    await billing.events.close();

    // The revoked entitlement remains absent after app relaunch offline.
    final offlineBilling = _FakeBilling()..online = false;
    final relaunched = AdFreePurchaseController(
      gateway: offlineBilling,
      verifier: verifier,
      offlineStore: cache(),
      clock: () => now,
    );
    await relaunched.initialize();
    expect(relaunched.isLicensed, false);
    relaunched.dispose();
    await offlineBilling.events.close();
  });

  test(
    'old remove_ads grants work without a separate license mechanism',
    () async {
      final keys = await _algorithm.newKeyPair();
      final key = _encode((await keys.extractPublicKey()).bytes);
      final cache = SignedOfflineEntitlementStore(
        publicKeyBase64: key,
        keyId: 'test-key-1',
        clock: () => _referenceTime,
      );
      await cache.initialize();
      final grant = await _sign(
        keyPair: keys,
        deviceId: await cache.getDeviceId(),
        issued: _referenceTime,
        productId: 'remove_ads',
      );
      expect(await cache.accept(grant), true);
      expect(cache.hasValidGrant, true);
    },
  );
}
