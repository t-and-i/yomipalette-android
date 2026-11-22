import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// All application secrets must use the same Android storage backend.
/// flutter_secure_storage 9.x migrates entries to EncryptedSharedPreferences
/// when this mode is enabled. Mixing this with the default AndroidOptions
/// can make previously saved values appear missing after an app restart.
const AndroidOptions yomiPaletteAndroidSecureStorageOptions = AndroidOptions(
  encryptedSharedPreferences: true,
);
