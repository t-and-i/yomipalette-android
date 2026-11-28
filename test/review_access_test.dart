import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tts_text_mp3_mobile/services/review_access.dart';
import 'package:tts_text_mp3_mobile/services/signed_review_cache.dart';
import 'package:tts_text_mp3_mobile/screens/app_information_screen.dart';
import 'package:tts_text_mp3_mobile/services/ad_free_purchase.dart';
import 'package:tts_text_mp3_mobile/widgets/access_purchase_section.dart';
import 'package:tts_text_mp3_mobile/l10n/strings.dart';

String encode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

class _ScreenStore implements ReviewEntitlementStore {
  bool active = false;
  @override
  bool get hasValidGrant => active;
  @override
  DateTime? get grantExpiresAt => DateTime.now().add(const Duration(hours: 72));
  @override
  Future<void> initialize() async {}
  @override
  Future<String> getDeviceId() async => 'a' * 43;
  @override
  Future<void> refresh() async {}
  @override
  Future<bool> accept(String signedGrant) async => active = true;
  @override
  Future<void> clear() async {
    active = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'About entry activates review access and hides purchase actions',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final review = ReviewAccessController(
        store: _ScreenStore(),
        endpoint: Uri.parse('https://example.test/review'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'active',
              'credential': 'r' * 43,
              'grant': 'screen-test-grant',
            }),
            200,
          ),
        ),
      );
      final purchase = AdFreePurchaseController();
      await review.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: AppInformationScreen(
            version: 'test',
            buildNumber: '1',
            openProject: () {},
            reviewController: review,
          ),
        ),
      );
      await tester.tap(find.text('Google Play review'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'console-token');
      await tester.tap(find.text('Activate review access'));
      await tester.pumpAndSettle();
      expect(find.text('Review access'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: review,
              builder: (_, _) => AccessPurchaseSection(
                purchase: purchase,
                review: review,
                strings: AppStrings(const Locale('en')),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Review access'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      await review.endAccess();
      await tester.pump();
      expect(find.text('Review access'), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      review.dispose();
      purchase.dispose();
    },
  );

  test(
    'review signature is scoped, expires at 72h and survives restart',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final algorithm = Ed25519();
      final keys = await algorithm.newKeyPair();
      final pub = encode((await keys.extractPublicKey()).bytes);
      var now = DateTime.now().toUtc();
      final issued = now.millisecondsSinceEpoch ~/ 1000;
      SignedReviewEntitlementStore store({String device = 'a'}) =>
          SignedReviewEntitlementStore(
            deviceIdProvider: () async => device * 43,
            publicKeyBase64: pub,
            keyId: 'test-review',
            clock: () => now,
          );
      Future<String> grant({
        String kind = 'review',
        int version = 3,
        int duration = 72 * 3600,
      }) async {
        final payload = utf8.encode(
          jsonEncode({
            'v': version,
            'kind': kind,
            'kid': 'test-review',
            'pkg': 'com.tjsongwei.tts_text_mp3_mobile',
            'deviceId': 'a' * 43,
            'iat': issued,
            'exp': issued + duration,
          }),
        );
        final signature = await algorithm.sign(payload, keyPair: keys);
        return '${encode(payload)}.${encode(signature.bytes)}';
      }

      final original = store();
      await original.initialize();
      final signed = await grant();
      expect(await original.accept(signed), isTrue);
      final restored = store();
      await restored.initialize();
      expect(restored.hasValidGrant, isTrue);
      expect(
        await restored.accept(await grant(kind: 'trial', version: 2)),
        isFalse,
      );
      expect(await restored.accept(await grant(duration: 73 * 3600)), isFalse);
      expect(await restored.accept('$signed-invalid'), isFalse);
      final other = store(device: 'b');
      await other.initialize();
      expect(await other.accept(signed), isFalse);
      now = now.add(const Duration(hours: 72));
      expect(restored.hasValidGrant, isFalse);
      now = now.subtract(const Duration(hours: 73));
      await restored.refresh();
      expect(restored.hasValidGrant, isFalse);
    },
  );

  test(
    'registration, restart, outage, expiry recovery and explicit revocation',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'unrelated-purchase': 'preserved',
      });
      final algorithm = Ed25519();
      final keys = await algorithm.newKeyPair();
      final pub = encode((await keys.extractPublicKey()).bytes);
      var now = DateTime.now().toUtc();
      var status = 200;
      final requests = <Map<String, dynamic>>[];
      ReviewAccessController controller() => ReviewAccessController(
        endpoint: Uri.parse('https://example.test/review'),
        store: SignedReviewEntitlementStore(
          deviceIdProvider: () async => 'a' * 43,
          publicKeyBase64: pub,
          keyId: 'review-test',
          clock: () => now,
        ),
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(body);
          if (status != 200) return http.Response('{}', status);
          final issued = now.millisecondsSinceEpoch ~/ 1000;
          final payload = utf8.encode(
            jsonEncode({
              'v': 3,
              'kind': 'review',
              'kid': 'review-test',
              'pkg': 'com.tjsongwei.tts_text_mp3_mobile',
              'deviceId': 'a' * 43,
              'iat': issued,
              'exp': issued + 72 * 3600,
            }),
          );
          final signature = await algorithm.sign(payload, keyPair: keys);
          return http.Response(
            jsonEncode({
              'status': 'active',
              'grant': '${encode(payload)}.${encode(signature.bytes)}',
              if (body['action'] == 'register') 'credential': 'r' * 43,
            }),
            200,
          );
        }),
      );
      final first = controller();
      await first.register('console-token');
      expect(first.isActive, isTrue);
      expect(
        (await const FlutterSecureStorage().readAll()).values,
        isNot(contains('console-token')),
      );
      first.dispose();
      final restored = controller();
      await restored.initialize();
      expect(restored.isActive, isTrue);
      status = 503;
      await restored.refresh(force: true);
      expect(restored.isActive, isTrue);
      expect(restored.hasCredential, isTrue);
      now = now.add(const Duration(hours: 73));
      expect(restored.isActive, isFalse);
      status = 200;
      await restored.refresh(force: true);
      expect(restored.isActive, isTrue);
      expect(requests.last['token'], isNull);
      expect(requests.last['credential'], 'r' * 43);
      status = 401;
      await restored.refresh(force: true);
      expect(restored.hasCredential, isFalse);
      expect(restored.isActive, isFalse);
      expect(
        await const FlutterSecureStorage().read(key: 'unrelated-purchase'),
        'preserved',
      );
      restored.dispose();
    },
  );
}
