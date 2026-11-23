import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'purchase_verifier.dart';

/// Only the OIDC ID token is sent to our Worker. No Google API scopes are asked.
const googleTrialWebClientId = String.fromEnvironment(
  'YOMIPALETTE_GOOGLE_WEB_CLIENT_ID',
);

abstract interface class TrialIdentityProvider {
  Future<String?> signIn();
  Future<String?> signInSilently();
  Future<void> signOut();
}

class GoogleTrialIdentityProvider implements TrialIdentityProvider {
  static Future<void>? _initialization;
  final GoogleSignIn _google = GoogleSignIn.instance;

  Future<void> _ready() {
    if (googleTrialWebClientId.isEmpty) {
      throw StateError('Google trial sign-in is not configured.');
    }
    return _initialization ??= _google.initialize(
      serverClientId: googleTrialWebClientId,
    );
  }

  @override
  Future<String?> signIn() async {
    await _ready();
    if (!_google.supportsAuthenticate()) {
      throw StateError('Google account selection is unavailable.');
    }
    final account = await _google.authenticate();
    return account.authentication.idToken;
  }

  @override
  Future<String?> signInSilently() async {
    await _ready();
    final attempt = _google.attemptLightweightAuthentication();
    if (attempt == null) return null;
    final account = await attempt;
    return account?.authentication.idToken;
  }

  @override
  Future<void> signOut() async {
    await _ready();
    await _google.signOut();
  }
}

enum TrialVerificationStatus { active, expired, blocked, unavailable }

class TrialVerificationOutcome {
  const TrialVerificationOutcome(this.status, {this.grant});
  final TrialVerificationStatus status;
  final String? grant;
}

abstract interface class TrialVerifier {
  Future<TrialVerificationOutcome> verify({
    required String idToken,
    required String deviceId,
  });
  void dispose();
}

class UnconfiguredTrialVerifier implements TrialVerifier {
  const UnconfiguredTrialVerifier();

  @override
  Future<TrialVerificationOutcome> verify({
    required String idToken,
    required String deviceId,
  }) async =>
      const TrialVerificationOutcome(TrialVerificationStatus.unavailable);

  @override
  void dispose() {}
}

class BackendTrialVerifier implements TrialVerifier {
  BackendTrialVerifier({
    required this.endpoint,
    http.Client? client,
    Future<String?> Function(String hash)? integrityToken,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _integrityToken = integrityToken ?? _requestIntegrityToken {
    if (endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.path != '/trial') {
      throw ArgumentError(
        'Trial verification requires the HTTPS /trial endpoint',
      );
    }
  }

  final Uri endpoint;
  final http.Client _client;
  final bool _ownsClient;
  final Future<String?> Function(String hash) _integrityToken;
  static const _channel = MethodChannel('tts_text_mp3/play_integrity');

  static Future<String?> _requestIntegrityToken(String requestHash) =>
      _channel.invokeMethod<String>('requestToken', {
        'cloudProjectNumber': playIntegrityProjectNumber,
        'requestHash': requestHash,
      });

  @override
  Future<TrialVerificationOutcome> verify({
    required String idToken,
    required String deviceId,
  }) async {
    const unavailable = TrialVerificationOutcome(
      TrialVerificationStatus.unavailable,
    );
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(deviceId) ||
        idToken.length < 80 ||
        idToken.length > 8192) {
      return unavailable;
    }
    try {
      final random = Random.secure();
      final requestId = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final hash = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                'yomipalette:/trial:v1',
                billingPackageName,
                sha256.convert(utf8.encode(idToken)).toString(),
                requestId,
                deviceId,
              ]),
            ),
          )
          .toString();
      final integrityToken = await _integrityToken(hash)
          .timeout(const Duration(seconds: 60));
      if (integrityToken == null || integrityToken.isEmpty) return unavailable;
      final response = await _client
          .post(
            endpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'packageName': billingPackageName,
              'deviceId': deviceId,
              'googleIdToken': idToken,
              'requestId': requestId,
              'integrityToken': integrityToken,
            }),
          )
          .timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) return unavailable;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return unavailable;
      return switch (decoded['status']) {
        'active' when decoded['offlineGrant'] is String =>
          TrialVerificationOutcome(
            TrialVerificationStatus.active,
            grant: decoded['offlineGrant'] as String,
          ),
        'expired' => const TrialVerificationOutcome(
          TrialVerificationStatus.expired,
        ),
        'blocked' => const TrialVerificationOutcome(
          TrialVerificationStatus.blocked,
        ),
        _ => unavailable,
      };
    } catch (_) {
      return unavailable; // Never log tokens, request bodies or exceptions.
    }
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }
}

TrialVerifier createTrialVerifier() {
  if (googleTrialWebClientId.isEmpty ||
      billingVerificationUrl.isEmpty ||
      (int.tryParse(playIntegrityProjectNumber) ?? 0) <= 0) {
    return const UnconfiguredTrialVerifier();
  }
  final verifyUrl = Uri.tryParse(billingVerificationUrl);
  if (verifyUrl == null ||
      verifyUrl.scheme != 'https' ||
      verifyUrl.host.isEmpty ||
      verifyUrl.path != '/verify') {
    return const UnconfiguredTrialVerifier();
  }
  return BackendTrialVerifier(endpoint: verifyUrl.replace(path: '/trial'));
}
