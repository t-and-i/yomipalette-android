import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';

/// A QA-only escape hatch. Never enable it in a production Play release.
const bool billingQaMode = bool.fromEnvironment(
  'YOMIPALETTE_BILLING_QA',
  defaultValue: kDebugMode,
);

const String billingVerificationUrl = String.fromEnvironment(
  'YOMIPALETTE_BILLING_VERIFY_URL',
);

const String playIntegrityProjectNumber = String.fromEnvironment(
  'YOMIPALETTE_PLAY_INTEGRITY_PROJECT_NUMBER',
);

const _integrityChannel = MethodChannel('tts_text_mp3/play_integrity');

Future<String?> _requestIntegrityToken(String requestHash) =>
    _integrityChannel.invokeMethod<String>('requestToken', {
      'cloudProjectNumber': playIntegrityProjectNumber,
      'requestHash': requestHash,
    });

const String billingPackageName = 'com.tjsongwei.tts_text_mp3_mobile';

enum PurchaseVerificationResult { verified, rejected, unavailable }

abstract interface class PurchaseVerifier {
  Future<PurchaseVerificationResult> verify(PurchaseDetails purchase);
  void dispose();
}

/// The test verifier intentionally does NOT prove that payment was made.
/// It must only be used in debug / explicitly tagged internal-QA builds.
class QaPurchaseVerifier implements PurchaseVerifier {
  const QaPurchaseVerifier();

  @override
  Future<PurchaseVerificationResult> verify(PurchaseDetails purchase) async =>
      purchase.verificationData.serverVerificationData.isNotEmpty
      ? PurchaseVerificationResult.verified
      : PurchaseVerificationResult.rejected;

  @override
  void dispose() {}
}

class UnconfiguredPurchaseVerifier implements PurchaseVerifier {
  const UnconfiguredPurchaseVerifier();

  @override
  Future<PurchaseVerificationResult> verify(PurchaseDetails purchase) async =>
      PurchaseVerificationResult.unavailable;

  @override
  void dispose() {}
}

/// Calls a trusted backend which independently checks the purchase token
/// against the Google Play Developer API. The server MUST verify package ID,
/// product ID, PURCHASED state, cancellation/refunds and request integrity.
///
/// Do not embed a Google Play service account or other API secrets in the app.
/// HTTP and invalid/unexpected responses fail closed.
class BackendPurchaseVerifier implements PurchaseVerifier {
  BackendPurchaseVerifier({
    required Uri endpoint,
    http.Client? client,
    Future<String?> Function(String requestHash)? integrityToken,
  }) : _endpoint = endpoint,
       _integrityToken = integrityToken ?? _requestIntegrityToken,
       _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (endpoint.scheme != 'https' || endpoint.host.isEmpty) {
      throw ArgumentError('Purchase verification requires an HTTPS endpoint.');
    }
  }

  final Uri _endpoint;
  final Future<String?> Function(String) _integrityToken;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<PurchaseVerificationResult> verify(PurchaseDetails purchase) async {
    final token = purchase.verificationData.serverVerificationData;
    if (token.isEmpty) return PurchaseVerificationResult.rejected;
    try {
      final random = Random.secure();
      final requestId = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      // The Worker computes this same versioned digest from the received fields.
      final requestHash = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                'yomipalette:/verify:v1',
                billingPackageName,
                purchase.productID,
                sha256.convert(utf8.encode(token)).toString(),
                requestId,
              ]),
            ),
          )
          .toString();
      final integrityToken = await _integrityToken(requestHash)
          .timeout(const Duration(seconds: 60));
      if (integrityToken == null || integrityToken.isEmpty) {
        return PurchaseVerificationResult.unavailable;
      }

      final response = await _client
          .post(
            _endpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'packageName': billingPackageName,
              'productId': purchase.productID,
              'purchaseToken': token,
              'requestId': requestId,
              'integrityToken': integrityToken,
            }),
          )
          .timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) {
        return PurchaseVerificationResult.unavailable;
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        return PurchaseVerificationResult.unavailable;
      }
      return switch (body['status']) {
        'verified' => PurchaseVerificationResult.verified,
        'rejected' => PurchaseVerificationResult.rejected,
        _ => PurchaseVerificationResult.unavailable,
      };
    } catch (_) {
      return PurchaseVerificationResult.unavailable;
    }
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }
}

PurchaseVerifier createPurchaseVerifier() {
  if (billingQaMode) return const QaPurchaseVerifier();
  if (billingVerificationUrl.isEmpty ||
      (int.tryParse(playIntegrityProjectNumber) ?? 0) <= 0) {
    return const UnconfiguredPurchaseVerifier();
  }
  final uri = Uri.tryParse(billingVerificationUrl);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    return const UnconfiguredPurchaseVerifier();
  }
  return BackendPurchaseVerifier(endpoint: uri);
}
