import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';

import 'offline_entitlement_cache.dart';

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

class PurchaseVerificationOutcome {
  const PurchaseVerificationOutcome(this.result, {this.offlineGrant});

  final PurchaseVerificationResult result;
  final String? offlineGrant;
}

abstract interface class PurchaseVerifier {
  Future<PurchaseVerificationResult> verify(PurchaseDetails purchase);
  void dispose();
}

/// Only a backend that binds the integrity verdict to a device ID may
/// provide a signed offline entitlement. Legacy QA verifiers do not.
abstract interface class OfflineGrantPurchaseVerifier {
  Future<PurchaseVerificationOutcome> verifyForDevice(
    PurchaseDetails purchase,
    String deviceId,
  );
}

/// The test verifier intentionally does NOT prove that payment was made.
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

/// Validates with a Worker, which checks Play Developer API, Play Integrity
/// and revoked purchases before signing an installation-scoped grant.
class BackendPurchaseVerifier
    implements PurchaseVerifier, OfflineGrantPurchaseVerifier {
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
  Future<PurchaseVerificationResult> verify(PurchaseDetails purchase) async =>
      (await _verify(purchase)).result;

  @override
  Future<PurchaseVerificationOutcome> verifyForDevice(
    PurchaseDetails purchase,
    String deviceId,
  ) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(deviceId)) {
      return const PurchaseVerificationOutcome(
        PurchaseVerificationResult.unavailable,
      );
    }
    return _verify(purchase, deviceId: deviceId);
  }

  Future<PurchaseVerificationOutcome> _verify(
    PurchaseDetails purchase, {
    String? deviceId,
  }) async {
    const unavailable = PurchaseVerificationOutcome(
      PurchaseVerificationResult.unavailable,
    );
    final token = purchase.verificationData.serverVerificationData;
    if (token.isEmpty) {
      return const PurchaseVerificationOutcome(
        PurchaseVerificationResult.rejected,
      );
    }
    try {
      final random = Random.secure();
      final requestId = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      // v2 binds the new device ID to the Play Integrity request hash.
      // v1 remains supported for installed legacy app versions.
      final requestHash = sha256
          .convert(
            utf8.encode(
              jsonEncode(
                deviceId == null
                    ? [
                        'yomipalette:/verify:v1',
                        billingPackageName,
                        purchase.productID,
                        sha256.convert(utf8.encode(token)).toString(),
                        requestId,
                      ]
                    : [
                        'yomipalette:/verify:v2',
                        billingPackageName,
                        purchase.productID,
                        sha256.convert(utf8.encode(token)).toString(),
                        requestId,
                        deviceId,
                      ],
              ),
            ),
          )
          .toString();
      final integrityToken = await _integrityToken(requestHash)
          .timeout(const Duration(seconds: 60));
      if (integrityToken == null || integrityToken.isEmpty) {
        return unavailable;
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
              if (deviceId != null) 'deviceId': deviceId,
            }),
          )
          .timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) return unavailable;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return unavailable;
      return switch (body['status']) {
        'verified' => PurchaseVerificationOutcome(
          PurchaseVerificationResult.verified,
          offlineGrant: body['offlineGrant'] is String
              ? body['offlineGrant'] as String
              : null,
        ),
        'rejected' => const PurchaseVerificationOutcome(
          PurchaseVerificationResult.rejected,
        ),
        _ => unavailable,
      };
    } catch (_) {
      return unavailable;
    }
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }
}

PurchaseVerifier createPurchaseVerifier() {
  if (billingQaMode) return const QaPurchaseVerifier();
  // Refuse to sell a permanent license if this build cannot validate a
  // backend-issued offline grant. The release build scripts enforce this too.
  if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(offlineGrantPublicKey) ||
      !RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch(offlineGrantKeyId)) {
    return const UnconfiguredPurchaseVerifier();
  }
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
