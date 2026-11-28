import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tts_text_mp3_mobile/services/trial_verifier.dart';

void main() {
  final endpoint = Uri.parse('https://example.invalid/trial');
  final idToken = 'a' * 120;
  final deviceId = 'D' * 43;

  test(
    'trial verification binds Google ID token, device and request nonce',
    () async {
      var calls = 0;
      String? requestHash;
      final client = MockClient((request) async {
        calls++;
        expect(request.method, 'POST');
        expect(request.url, endpoint);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['packageName'], 'com.tjsongwei.tts_text_mp3_mobile');
        expect(body['googleIdToken'], idToken);
        expect(body['deviceId'], deviceId);
        expect(body['integrityToken'], 'integrity-test-only');
        final requestId = body['requestId'] as String;
        expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(requestId), true);
        final expected = sha256
            .convert(
              utf8.encode(
                jsonEncode([
                  'yomipalette:/trial:v1',
                  'com.tjsongwei.tts_text_mp3_mobile',
                  sha256.convert(utf8.encode(idToken)).toString(),
                  requestId,
                  deviceId,
                ]),
              ),
            )
            .toString();
        expect(requestHash, expected);
        return http.Response(
          jsonEncode({
            'status': 'active',
            'offlineGrant': 'signed-trial-test-grant',
          }),
          200,
        );
      });
      final verifier = BackendTrialVerifier(
        endpoint: endpoint,
        client: client,
        integrityToken: (hash) async {
          requestHash = hash;
          return 'integrity-test-only';
        },
      );
      final response = await verifier.verify(
        idToken: idToken,
        deviceId: deviceId,
      );
      expect(response.status, TrialVerificationStatus.active);
      expect(response.grant, 'signed-trial-test-grant');
      expect(calls, 1);
      verifier.dispose();
    },
  );

  test('missing integrity proof does not contact the trial endpoint', () async {
    final client = MockClient((_) async {
      fail('Worker must not be contacted without Play Integrity proof');
    });
    final verifier = BackendTrialVerifier(
      endpoint: endpoint,
      client: client,
      integrityToken: (_) async => null,
    );
    final result = await verifier.verify(idToken: idToken, deviceId: deviceId);
    expect(result.status, TrialVerificationStatus.unavailable);
    verifier.dispose();
  });

  test('expired or blocked account is not considered trial access', () async {
    for (final status in ['expired', 'blocked']) {
      final verifier = BackendTrialVerifier(
        endpoint: endpoint,
        client: MockClient(
          (_) async => http.Response(jsonEncode({'status': status}), 200),
        ),
        integrityToken: (_) async => 'integrity-test-only',
      );
      final result = await verifier.verify(
        idToken: idToken,
        deviceId: deviceId,
      );
      expect(
        result.status,
        status == 'expired'
            ? TrialVerificationStatus.expired
            : TrialVerificationStatus.blocked,
      );
      expect(result.grant, null);
      verifier.dispose();
    }
  });

  test('missing grant and invalid endpoints never unlock trial', () async {
    expect(
      () =>
          BackendTrialVerifier(endpoint: Uri.parse('http://example.org/trial')),
      throwsArgumentError,
    );
    final verifier = BackendTrialVerifier(
      endpoint: endpoint,
      client: MockClient(
        (_) async => http.Response(jsonEncode({'status': 'active'}), 200),
      ),
      integrityToken: (_) async => 'integrity-test-only',
    );
    final result = await verifier.verify(idToken: idToken, deviceId: deviceId);
    expect(result.status, TrialVerificationStatus.unavailable);
    verifier.dispose();
  });
}
