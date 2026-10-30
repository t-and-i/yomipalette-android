import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_text_mp3_mobile/services/ad_free_purchase.dart';

class FakeBilling implements AdFreeBillingGateway {
  final controller = StreamController<List<PurchaseDetails>>.broadcast(
    sync: true,
  );
  bool storeAvailable = true;
  int restored = 0;
  int purchasesMade = 0;
  int completions = 0;

  @override
  Stream<List<PurchaseDetails>> get purchases => controller.stream;

  @override
  Future<bool> isAvailable() async => storeAvailable;

  @override
  Future<ProductDetailsResponse> queryProducts(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: [
          ProductDetails(
            id: adFreeProductId,
            title: 'Remove ads',
            description: 'One-time purchase',
            price: '¥500',
            rawPrice: 500,
            currencyCode: 'JPY',
          ),
        ],
        notFoundIDs: const [],
      );

  @override
  Future<bool> purchase(ProductDetails product) async {
    purchasesMade++;
    return true;
  }

  @override
  Future<void> restore() async {
    restored++;
  }

  @override
  Future<void> complete(PurchaseDetails purchase) async {
    completions++;
  }
}

PurchaseDetails record(
  PurchaseStatus status, {
  String token = 'valid-token',
  bool acknowledge = true,
  String id = adFreeProductId,
}) => PurchaseDetails(
  productID: id,
  purchaseID: 'order-1',
  verificationData: PurchaseVerificationData(
    localVerificationData: '{}',
    serverVerificationData: token,
    source: 'google_play',
  ),
  transactionDate: '1',
  status: status,
)..pendingCompletePurchase = acknowledge;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('product appears and store restores at startup', () async {
    final fake = FakeBilling();
    final controller = AdFreePurchaseController(gateway: fake);
    await controller.initialize();
    expect(controller.product?.id, adFreeProductId);
    expect(controller.product?.price, '¥500');
    expect(controller.canBuy, isTrue);
    expect(fake.restored, 1);
    controller.dispose();
    await fake.controller.close();
  });

  test('pending purchase does not remove ads', () async {
    final fake = FakeBilling();
    final controller = AdFreePurchaseController(gateway: fake);
    await controller.initialize();
    await controller.handleUpdates([record(PurchaseStatus.pending)]);
    expect(controller.isAdFree, isFalse);
    expect(fake.completions, 0);
    controller.dispose();
    await fake.controller.close();
  });

  test('purchase and restore unlock and acknowledge once', () async {
    final fake = FakeBilling();
    final controller = AdFreePurchaseController(gateway: fake);
    await controller.initialize();
    await controller.buy();
    expect(fake.purchasesMade, 1);
    await controller.handleUpdates([record(PurchaseStatus.purchased)]);
    expect(controller.isAdFree, isTrue);
    expect(fake.completions, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('ad_free_owned_v1'), isTrue);
    expect(controller.canBuy, isFalse);
    controller.dispose();
    await fake.controller.close();

    final restored = AdFreePurchaseController(gateway: FakeBilling());
    await restored.initialize();
    expect(restored.isAdFree, isTrue);
    restored.dispose();
  });

  test('empty receipt does not grant or acknowledge', () async {
    final fake = FakeBilling();
    final controller = AdFreePurchaseController(gateway: fake);
    await controller.initialize();
    await controller.handleUpdates([
      record(PurchaseStatus.restored, token: ''),
    ]);
    expect(controller.isAdFree, isFalse);
    expect(fake.completions, 0);
    controller.dispose();
    await fake.controller.close();
  });

  test('unrelated product does not grant ad-free entitlement', () async {
    final fake = FakeBilling();
    final controller = AdFreePurchaseController(gateway: fake);
    await controller.initialize();
    await controller.handleUpdates([
      record(PurchaseStatus.purchased, id: 'other_product'),
    ]);
    expect(controller.isAdFree, isFalse);
    controller.dispose();
    await fake.controller.close();
  });

  test('offline store disables purchasing', () async {
    final fake = FakeBilling()..storeAvailable = false;
    final controller = AdFreePurchaseController(gateway: fake);
    await controller.initialize();
    expect(controller.canBuy, isFalse);
    expect(controller.isAdFree, isFalse);
    controller.dispose();
    await fake.controller.close();
  });
}
