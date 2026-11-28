import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'purchase_verifier.dart';
import 'secure_storage_options.dart';
import 'signed_review_cache.dart';

const reviewAccessUrl = String.fromEnvironment('YOMIPALETTE_REVIEW_ACCESS_URL');

class ReviewAccessController extends ChangeNotifier {
  ReviewAccessController({
    ReviewEntitlementStore? store,
    FlutterSecureStorage? storage,
    http.Client? client,
    Uri? endpoint,
  }) : _store = store ?? SignedReviewEntitlementStore(),
       _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: yomiPaletteAndroidSecureStorageOptions,
           ),
       _client = client ?? http.Client(),
       _endpoint = endpoint ?? Uri.tryParse(reviewAccessUrl);

  static const _credentialKey = 'review_refresh_credential_v1';
  final ReviewEntitlementStore _store;
  final FlutterSecureStorage _storage;
  final http.Client _client;
  final Uri? _endpoint;
  String? _credential;
  Future<void>? _initialization;
  Timer? _timer;
  bool _disposed = false;
  bool busy = false;
  String? message;

  bool get isActive => hasCredential && _store.hasValidGrant;
  bool get hasCredential => _credential != null;
  bool get configured =>
      _endpoint?.scheme == 'https' &&
      _endpoint!.host.isNotEmpty &&
      _endpoint.userInfo.isEmpty;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      await _store.initialize();
      _credential = await _storage.read(key: _credentialKey);
      // A grant without its saved registration cannot survive partial writes.
      if (_credential == null) await _store.clear();
    } catch (_) {
      message = 'reviewUnavailable';
    }
    if (_disposed) return;
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(refresh());
    });
    _changed();
  }

  Future<void> register(String token) async {
    await initialize();
    if (busy || _disposed) return;
    await _request({'action': 'register', 'token': token.trim()});
  }

  Future<void> refresh({bool force = false}) async {
    await initialize();
    if (busy || _disposed) return;
    busy = true;
    try {
      await _store.refresh();
      if (_credential == null) return;
      final expiry = _store.grantExpiresAt;
      if (!force &&
          isActive &&
          expiry != null &&
          expiry.difference(DateTime.now()).inHours > 24) {
        return;
      }
      await _request({'action': 'refresh', 'credential': _credential});
    } catch (_) {
      message = 'reviewUnavailable';
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> _request(Map<String, String?> fields) async {
    busy = true;
    message = null;
    _changed();
    try {
      if (!configured) throw StateError('Review endpoint unavailable');
      final response = await _client
          .post(
            _endpoint!,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              ...fields,
              'packageName': billingPackageName,
              'deviceId': await _store.getDeviceId(),
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401) {
        if (fields['action'] == 'refresh') await _clear();
        message = 'reviewRejected';
        return;
      }
      if (response.statusCode != 200 || response.body.length > 8192) {
        throw StateError('Review service unavailable');
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> ||
          data['status'] != 'active' ||
          data['grant'] is! String) {
        throw StateError('Invalid review response');
      }
      final credential = fields['action'] == 'register'
          ? data['credential']
          : _credential;
      if (credential is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(credential)) {
        throw StateError('Invalid review credential');
      }
      if (!await _store.accept(data['grant'] as String)) {
        throw StateError('Invalid review grant');
      }
      await _storage.write(key: _credentialKey, value: credential);
      _credential = credential;
    } catch (_) {
      message = 'reviewUnavailable';
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> _clear() async {
    _credential = null;
    await _store.clear();
    await _storage.delete(key: _credentialKey);
  }

  Future<void> endAccess() async {
    await initialize();
    if (busy || _disposed) return;
    busy = true;
    try {
      await _clear();
      message = null;
    } catch (_) {
      message = 'reviewUnavailable';
    } finally {
      busy = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _client.close();
    super.dispose();
  }
}
