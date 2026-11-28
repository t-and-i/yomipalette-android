import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'offline_entitlement_cache.dart';
import 'secure_storage_options.dart';

// Public verification parameters. Private signing keys stay in the Worker.
const reviewGrantPublicKey = String.fromEnvironment(
  'YOMIPALETTE_REVIEW_GRANT_PUBLIC_KEY',
  defaultValue: offlineGrantPublicKey,
);
const reviewGrantKeyId = String.fromEnvironment(
  'YOMIPALETTE_REVIEW_GRANT_KEY_ID',
  defaultValue: offlineGrantKeyId,
);

/// A separate signed schema and storage namespace for review access.
abstract interface class ReviewEntitlementStore {
  Future<void> initialize();
  Future<String> getDeviceId();
  bool get hasValidGrant;
  DateTime? get grantExpiresAt;
  Future<bool> accept(String signedGrant);
  Future<void> refresh();
  Future<void> clear();
}

class SignedReviewEntitlementStore implements ReviewEntitlementStore {
  SignedReviewEntitlementStore({
    FlutterSecureStorage? storage,
    Future<String> Function()? deviceIdProvider,
    this._publicKeyBase64 = reviewGrantPublicKey,
    this._keyId = reviewGrantKeyId,
    DateTime Function()? clock,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: yomiPaletteAndroidSecureStorageOptions,
           ),
       _deviceIdProvider =
           deviceIdProvider ?? SignedOfflineEntitlementStore().getDeviceId,
       _clock = clock ?? DateTime.now;

  static const _grantKey = 'review_signed_grant_v1';
  // Shared high-water clock with the purchased entitlement. Do not delete it.
  static const _lastSeenKey = 'offline_entitlement_last_seen_v1';
  static const _package = 'com.tjsongwei.tts_text_mp3_mobile';
  static const _maxGrantSeconds = 72 * 3600;
  static const _skewMs = 5 * 60 * 1000;
  static const _rollbackToleranceMs = 60 * 1000;

  final FlutterSecureStorage _storage;
  final Future<String> Function() _deviceIdProvider;
  final String _publicKeyBase64;
  final String _keyId;
  final DateTime Function() _clock;

  String? _deviceId;
  Map<String, dynamic>? _claims;
  int? _lastSeenMs;
  bool _clockRollback = false;

  @override
  Future<String> getDeviceId() async => _deviceId ??= await _deviceIdProvider();

  @override
  DateTime? get grantExpiresAt => _time('exp');

  DateTime? _time(String field) {
    final value = _claims?[field];
    return value is int
        ? DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true)
        : null;
  }

  @override
  bool get hasValidGrant {
    final claims = _claims;
    if (claims == null || _clockRollback) return false;
    final now = _clock().toUtc().millisecondsSinceEpoch;
    final issued = (claims['iat'] as int) * 1000;
    final expires = (claims['exp'] as int) * 1000;
    return now >= issued - _skewMs &&
        now < expires &&
        (_lastSeenMs == null || now >= _lastSeenMs! - _rollbackToleranceMs);
  }

  @override
  Future<void> initialize() async {
    _deviceId = await getDeviceId();
    _lastSeenMs = int.tryParse(await _storage.read(key: _lastSeenKey) ?? '');
    final saved = await _storage.read(key: _grantKey);
    _claims = saved == null ? null : await _validate(saved);
    if (saved != null && _claims == null) await _storage.delete(key: _grantKey);
    await refresh();
  }

  @override
  Future<void> refresh() async {
    final now = _clock().toUtc().millisecondsSinceEpoch;
    final previous = _lastSeenMs;
    _clockRollback = previous != null && now < previous - _rollbackToleranceMs;
    if (previous == null || now > previous) {
      _lastSeenMs = now;
      await _storage.write(key: _lastSeenKey, value: '$now');
    }
  }

  @override
  Future<bool> accept(String signedGrant) async {
    final claims = await _validate(signedGrant);
    if (claims == null ||
        _clock().toUtc().millisecondsSinceEpoch >=
            (claims['exp'] as int) * 1000) {
      return false;
    }
    await refresh();
    if (_clockRollback) return false;
    await _storage.write(key: _grantKey, value: signedGrant);
    _claims = claims;
    return hasValidGrant;
  }

  @override
  Future<void> clear() async {
    _claims = null;
    await _storage.delete(key: _grantKey);
  }

  Future<Map<String, dynamic>?> _validate(String token) async {
    if (_deviceId == null ||
        _keyId.isEmpty ||
        _publicKeyBase64.length != 43 ||
        token.length > 4096) {
      return null;
    }
    final parts = token.split('.');
    if (parts.length != 2 ||
        parts.any((s) => !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(s))) {
      return null;
    }
    try {
      final keyBytes = base64Url.decode(base64Url.normalize(_publicKeyBase64));
      final bytes = base64Url.decode(base64Url.normalize(parts[0]));
      final signature = base64Url.decode(base64Url.normalize(parts[1]));
      if (keyBytes.length != 32 ||
          bytes.length > 2048 ||
          signature.length != 64) {
        return null;
      }
      final key = SimplePublicKey(keyBytes, type: KeyPairType.ed25519);
      final verified = await Ed25519().verify(
        bytes,
        signature: Signature(signature, publicKey: key),
      );
      if (!verified) return null;
      final parsed = jsonDecode(utf8.decode(bytes));
      if (parsed is! Map<String, dynamic>) return null;
      final issued = parsed['iat'];
      final exp = parsed['exp'];
      if (parsed['v'] != 3 ||
          parsed['kind'] != 'review' ||
          parsed['kid'] != _keyId ||
          parsed['pkg'] != _package ||
          parsed['deviceId'] != _deviceId ||
          parsed.containsKey('receiptHash') ||
          issued is! int ||
          exp is! int ||
          exp <= issued ||
          exp - issued != _maxGrantSeconds) {
        return null;
      }
      final now = _clock().toUtc().millisecondsSinceEpoch;
      if (issued * 1000 > now + _skewMs) return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }
}
