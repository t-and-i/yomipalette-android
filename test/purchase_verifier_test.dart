import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:tts_text_mp3_mobile/services/purchase_verifier.dart';

PurchaseDetails purchase({String token = 'sample-token'}) => PurchaseDetails(
  productID: 'remove_ads',
  purchaseID: 'order-test',
  verificationData: PurchaseVerificationData(
    localVerificationData: '{}',
    serverVerificationData: token,
    source: 'google_play',
  ),
  transactionDate: '1',
  status: PurchaseStatus.purchased,
);

void main() {
  final url = Uri.parse('https://example.test/verify');

  test('backend verifies matching purchase and package ID', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url, url);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['purchaseToken'], 'sample-token');
      expect(body['productId'], 'remove_ads');
      expect(body['packageName'], billingPackageName);
      return http.Response('{"status":"verified"}', 200);
    });
    final verifier = BackendPurchaseVerifier(endpoint: url, client: client);
    expect(
      await verifier.verify(purchase()),
      PurchaseVerificationResult.verified,
    );
    verifier.dispose();
    client.close();
  });

  test('backend rejection removes entitlement', () async {
    final verifier = BackendPurchaseVerifier(
      endpoint: url,
      client: MockClient(
        (request) async => http.Response('{"status":"rejected"}', 200),
      ),
    );
    expect(
      await verifier.verify(purchase()),
      PurchaseVerificationResult.rejected,
    );
    verifier.dispose();
  });

  test('server errors and malformed responses fail closed', () async {
    for (final response in [
      http.Response('Service unavailable', 503),
      http.Response('{"status":"unknown"}', 200),
      http.Response('bad json', 200),
    ]) {
      final verifier = BackendPurchaseVerifier(
        endpoint: url,
        client: MockClient((_) async => response),
      );
      expect(
        await verifier.verify(purchase()),
        PurchaseVerificationResult.unavailable,
      );
      verifier.dispose();
    }
  });

  test('empty token is rejected without contacting server', () async {
    final verifier = BackendPurchaseVerifier(
      endpoint: url,
      client: MockClient((_) async {
        fail('Must not send empty receipt to backend');
      }),
    );
    expect(
      await verifier.verify(purchase(token: '')),
      PurchaseVerificationResult.rejected,
    );
    verifier.dispose();
  });

  test('non-HTTPS verifier endpoint is forbidden', () {
    expect(
      () => BackendPurchaseVerifier(endpoint: Uri.parse('http://example.org')),
      throwsArgumentError,
    );
  });
}
