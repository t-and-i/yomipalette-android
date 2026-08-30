import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API credentials are deliberately kept out of SharedPreferences and files.
class CredentialStore {
  CredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.unlocked_this_device,
              ),
            );

  final FlutterSecureStorage _storage;
  final Map<String, String> _sessionOnly = {};

  String _key(String provider, String field) => 'credential.$provider.$field';

  Future<void> write(
    String provider,
    String field,
    String value, {
    required bool persist,
  }) async {
    final key = _key(provider, field);
    if (!persist) {
      _sessionOnly[key] = value;
      await _storage.delete(key: key);
      return;
    }
    _sessionOnly.remove(key);
    await _storage.write(key: key, value: value);
  }

  Future<String?> read(String provider, String field) async {
    final key = _key(provider, field);
    return _sessionOnly[key] ?? _storage.read(key: key);
  }

  Future<void> deleteProvider(String provider) async {
    _sessionOnly
        .removeWhere((key, _) => key.startsWith('credential.$provider.'));
    final values = await _storage.readAll();
    for (final key in values.keys.where(
      (key) => key.startsWith('credential.$provider.'),
    )) {
      await _storage.delete(key: key);
    }
  }

  void clearSession() => _sessionOnly.clear();
}
