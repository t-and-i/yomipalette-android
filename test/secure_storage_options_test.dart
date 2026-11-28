import 'package:flutter_test/flutter_test.dart';
import 'package:tts_text_mp3_mobile/services/secure_storage_options.dart';

void main() {
  test('all Android secrets use durable encrypted SharedPreferences', () {
    final options = yomiPaletteAndroidSecureStorageOptions.toMap();
    expect(options['encryptedSharedPreferences'], 'true');
    // Never erase a valid purchase because a keystore read failed.
    expect(options['resetOnError'], 'false');
    expect(options['sharedPreferencesName'], '');
    expect(options['preferencesKeyPrefix'], '');
  });
}
