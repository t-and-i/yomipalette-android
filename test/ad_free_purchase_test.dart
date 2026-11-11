import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_text_mp3_mobile/screens/home_screen.dart';
import 'package:tts_text_mp3_mobile/services/ad_free_purchase.dart';
import 'package:tts_text_mp3_mobile/widgets/ad_free_section.dart';
import 'package:tts_text_mp3_mobile/services/purchase_verifier.dart';

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

class FakeVerifier implements PurchaseVerifier {
  FakeVerifier(this.result);
  PurchaseVerificationResult result;
  int calls = 0;

  @override
  Future<PurchaseVerificationResult> verify(PurchaseDetails purchase) async {
    calls++;
    return result;
  }

  @override
  void dispose() {}
}

class DelayedVerifier implements PurchaseVerifier {
  final first = Completer<PurchaseVerificationResult>();
  int calls = 0;

  @override
  Future<PurchaseVerificationResult> verify(PurchaseDetails purchase) async {
    calls++;
    if (calls == 1) return first.future;
    return PurchaseVerificationResult.verified;
  }

  @override
  void dispose() {}
}

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

  testWidgets('verified buyers do not see the ad-free purchase section', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    FlutterSecureStorage.setMockInitialValues({});
    final fake = FakeBilling();
    final controller = AdFreePurchaseController(
      gateway: fake,
      verifier: FakeVerifier(PurchaseVerificationResult.verified),
    );
    await controller.initialize();

    Widget screen() => MaterialApp(
      home: HomeScreen(onLocaleChanged: (_) {}, adFreeController: controller),
    );
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Remove ads (one-time purchase)'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(AdFreeSection), findsOneWidget);

    await controller.handleUpdates([record(PurchaseStatus.purchased)]);
    expect(controller.isAdFree, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Appearance'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(AdFreeSection), findsNothing);
    expect(find.text('Restore purchases'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await fake.controller.close();
    debugDefaultTargetPlatformOverride = null;
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

  test('server rejection never unlocks and never acknowledges', () async {
    final fake = FakeBilling();
    final verifier = FakeVerifier(PurchaseVerificationResult.rejected);
    final controller = AdFreePurchaseController(
      gateway: fake,
      verifier: verifier,
    );
    await controller.initialize();
    await controller.handleUpdates([record(PurchaseStatus.purchased)]);
    expect(controller.isAdFree, isFalse);
    expect(fake.completions, 0);
    expect(verifier.calls, 1);
    controller.dispose();
    await fake.controller.close();
  });

  test('temporary verifier failure does not acknowledge', () async {
    final fake = FakeBilling();
    final verifier = FakeVerifier(PurchaseVerificationResult.unavailable);
    final controller = AdFreePurchaseController(
      gateway: fake,
      verifier: verifier,
    );
    await controller.initialize();
    await controller.handleUpdates([record(PurchaseStatus.purchased)]);
    expect(controller.isAdFree, isFalse);
    expect(controller.busy, isFalse);
    expect(fake.completions, 0);
    verifier.result = PurchaseVerificationResult.verified;
    await controller.handleUpdates([record(PurchaseStatus.restored)]);
    expect(controller.isAdFree, isTrue);
    expect(fake.completions, 1);
    controller.dispose();
    await fake.controller.close();
  });

  test(
    'concurrent duplicate events are serialized and acknowledged once',
    () async {
      final fake = FakeBilling();
      final verifier = DelayedVerifier();
      final controller = AdFreePurchaseController(
        gateway: fake,
        verifier: verifier,
      );
      await controller.initialize();
      final first = controller.handleUpdates([
        record(PurchaseStatus.purchased),
      ]);
      final second = controller.handleUpdates([
        record(PurchaseStatus.restored),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(verifier.calls, 1);
      verifier.first.complete(PurchaseVerificationResult.verified);
      await Future.wait([first, second]);
      expect(verifier.calls, 2);
      expect(fake.completions, 1);
      expect(controller.isAdFree, isTrue);
      controller.dispose();
      await fake.controller.close();
    },
  );

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
