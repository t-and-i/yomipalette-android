import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const offlineGrantPublicKey = String.fromEnvironment(
  'YOMIPALETTE_OFFLINE_GRANT_PUBLIC_KEY',
);
const offlineGrantKeyId = String.fromEnvironment(
  'YOMIPALETTE_OFFLINE_GRANT_KEY_ID',
);

const offlineGrantLifetime = Duration(hours: 72);
const _allowedClockSkew = Duration(minutes: 5);
const _rollbackTolerance = Duration(minutes: 1);
const _expectedPackage = 'com.tjsongwei.tts_text_mp3_mobile';

class CachedPurchase {
  const CachedPurchase(this.productId, this.token);
  final String productId;
  final String token;
}

abstract interface class OfflineEntitlementStore {
  Future<void> initialize();
  Future<String> getDeviceId();
  bool get hasValidGrant;
  Future<bool> accept(String signedGrant);
  Future<void> rememberPurchase(String productId, String token);
  Future<CachedPurchase?> getCachedPurchase();
  Future<void> refresh();
  Future<void> clear();
}

/// Caches ONLY a Worker-signed entitlement. The Ed25519 public key is compiled
/// into the app; no private key is stored here. Keystore-backed storage
/// holds the installation ID, signed grant and receipt for re-verification.
class SignedOfflineEntitlementStore implements OfflineEntitlementStore {
  SignedOfflineEntitlementStore({
    FlutterSecureStorage? storage,
    this._publicKeyBase64 = offlineGrantPublicKey,
    this._keyId = offlineGrantKeyId,
    DateTime Function()? clock,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _clock = clock ?? DateTime.now;

  static const _deviceKey = 'offline_entitlement_device_v1';
  static const _grantKey = 'offline_entitlement_grant_v1';
  static const _lastSeenKey = 'offline_entitlement_last_seen_v1';
  static const _cachedPurchaseKey = 'offline_entitlement_purchase_v1';

  final FlutterSecureStorage _storage;
  final String _publicKeyBase64;
  final String _keyId;
  final DateTime Function() _clock;
  String? _deviceId;
  Future<String>? _loadingDevice;
  Map<String, dynamic>? _claims;
  int? _lastSeenMs;
  bool _clockRollback = false;

  static String _randomDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static bool _validDeviceId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value);

  @override
  Future<String> getDeviceId() => _loadingDevice ??= _readDeviceId();

  Future<String> _readDeviceId() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null && _validDeviceId(existing)) {
      _deviceId = existing;
      return existing;
    }
    final generated = _randomDeviceId();
    await _storage.write(key: _deviceKey, value: generated);
    _deviceId = generated;
    return generated;
  }

  @override
  Future<void> initialize() async {
    await getDeviceId();
    _lastSeenMs = int.tryParse(await _storage.read(key: _lastSeenKey) ?? '');
    final saved = await _storage.read(key: _grantKey);
    _claims = saved == null ? null : await _validate(saved);
    if (saved != null && _claims == null) {
      await _storage.delete(key: _grantKey);
    }
    await refresh();
  }

  @override
  bool get hasValidGrant {
    final claims = _claims;
    if (claims == null || _clockRollback) return false;
    final now = _clock().toUtc().millisecondsSinceEpoch;
    final iat = (claims['iat'] as int) * 1000;
    final exp = (claims['exp'] as int) * 1000;
    // Wall-clock rollback detection is best effort; a rooted device can
    // defeat local time/storage. Never extend a signed expiry locally.
    return now >= iat - _allowedClockSkew.inMilliseconds &&
        now < exp &&
        (_lastSeenMs == null ||
            now >= _lastSeenMs! - _rollbackTolerance.inMilliseconds);
  }

  @override
  Future<void> refresh() async {
    final now = _clock().toUtc().millisecondsSinceEpoch;
    final previous = _lastSeenMs;
    _clockRollback =
        previous != null && now < previous - _rollbackTolerance.inMilliseconds;
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
  Future<void> rememberPurchase(String productId, String token) async {
    if ((productId != 'full_access' && productId != 'remove_ads') ||
        token.length < 8 ||
        token.length > 4096 ||
        _claims == null ||
        _claims!['productId'] != productId ||
        hashes.sha256.convert(utf8.encode(token)).toString() !=
            _claims!['receiptHash']) {
      throw ArgumentError('Purchase does not match the signed grant.');
    }
    // Only re-send this encrypted receipt to the authenticated Worker to
    // refresh/revoke an already verified grant. It is never proof by itself.
    await _storage.write(
      key: _cachedPurchaseKey,
      value: jsonEncode({'productId': productId, 'token': token}),
    );
  }

  @override
  Future<CachedPurchase?> getCachedPurchase() async {
    final saved = await _storage.read(key: _cachedPurchaseKey);
    if (saved == null || _claims == null) return null;
    try {
      final decoded = jsonDecode(saved);
      if (decoded is! Map<String, dynamic> ||
          decoded['productId'] != _claims!['productId'] ||
          decoded['token'] is! String ||
          (decoded['token'] as String).length < 8 ||
          (decoded['token'] as String).length > 4096) {
        return null;
      }
      final token = decoded['token'] as String;
      final digest = hashes.sha256.convert(utf8.encode(token)).toString();
      if (digest != _claims!['receiptHash']) return null;
      return CachedPurchase(decoded['productId'] as String, token);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    _claims = null;
    await _storage.delete(key: _grantKey);
    await _storage.delete(key: _cachedPurchaseKey);
    // Preserve device ID and high-water clock to prevent cache replay.
  }

  Future<Map<String, dynamic>?> _validate(String token) async {
    if (token.length > 4096 ||
        _keyId.isEmpty ||
        _publicKeyBase64.isEmpty ||
        _deviceId == null) {
      return null;
    }
    final parts = token.split('.');
    if (parts.length != 2 ||
        parts.any((p) => !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(p))) {
      return null;
    }
    try {
      final publicBytes = base64Url.decode(
        base64Url.normalize(_publicKeyBase64),
      );
      if (publicBytes.length != 32) return null;
      final payload = base64Url.decode(base64Url.normalize(parts[0]));
      final signature = base64Url.decode(base64Url.normalize(parts[1]));
      if (signature.length != 64 || payload.length > 2048) return null;
      final key = SimplePublicKey(publicBytes, type: KeyPairType.ed25519);
      if (!await Ed25519().verify(
        payload,
        signature: Signature(signature, publicKey: key),
      )) {
        return null;
      }
      final json = jsonDecode(utf8.decode(payload));
      if (json is! Map<String, dynamic>) return null;
      final iat = json['iat'];
      final exp = json['exp'];
      if (json['v'] != 1 ||
          json['kid'] != _keyId ||
          json['pkg'] != _expectedPackage ||
          (json['productId'] != 'full_access' &&
              json['productId'] != 'remove_ads') ||
          json['deviceId'] != _deviceId ||
          json['receiptHash'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(json['receiptHash'] as String) ||
          iat is! int ||
          exp is! int ||
          exp - iat != offlineGrantLifetime.inSeconds) {
        return null;
      }
      final now = _clock().toUtc().millisecondsSinceEpoch;
      if (iat * 1000 > now + _allowedClockSkew.inMilliseconds) {
        return null;
      }
      return json;
    } catch (_) {
      return null;
    }
  }
}
