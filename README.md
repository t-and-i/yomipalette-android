# TTS Text to MP3 Mobile

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

Flutter client for Android and iOS, maintained as a separate project under `mobile/` in the desktop repository.

## Initial scope

- TXT and EPUB input. TXT supports automatic detection and manual selection of UTF-8, UTF-16, UTF-32, CP932/Shift_JIS, GB18030, and Big5
- Split by chapter or character limit (default: 5000)
- Approximately 15-second preview from the selected unit, or the first unit
- Edge TTS, Azure Speech, Google Cloud TTS, and installed Android TTS engines
- Credentials stored in Android Keystore/iOS Keychain or kept for the session only
- MP3 generation, app-document storage, and system sharing
- Direct output to a user-selected folder, with persisted Android folder permission
- Resume from the first unfinished unit after a quota or network failure
- English, Japanese, and Simplified Chinese UI

TXT encoding defaults to automatic detection. If the result is incorrect, select an encoding in the TXT character-encoding field to reload the original file bytes. Encoding detection cannot be perfect for every legacy file. EPUB processing is unaffected.

Select an output folder to save there directly. If no folder is selected, files are created in app storage and shared; after the share sheet closes, the app asks whether to delete the current app copies. Kept copies are removed when the app is uninstalled or its data is cleared.

## Unsupported features and reasons

- **Google service-account JSON:** not accepted because it contains a reusable private key. Secure storage protects data at rest but cannot guarantee protection while a rooted/jailbroken device or runtime hook observes the app using it. Google mobile support is API-key-only.
- **OpenAI:** deferred because OpenAI advises against exposing secret API keys in client-side apps. Keystore/Keychain does not eliminate runtime extraction. It can be reconsidered with a backend relay.
- **Edge TTS:** available without an API key. It uses the same unofficial Microsoft Edge Read Aloud service family as the desktop provider, not a supported public Flutter SDK, so a service-side protocol change can break it without notice. Use Azure Speech where a supported service contract is required.
- **Android device TTS:** Android only. The app lists enabled TTS engines and their available voices instead of requiring Samsung TTS specifically. Language data may need to be installed in Android settings. Device synthesis is converted from 16-bit PCM WAV to MP3 with the bundled LAME encoder; engines that return another file format are reported as unsupported.

These restrictions apply only to the mobile project. Desktop providers remain unchanged. See [the Japanese README](README.ja.md) for the complete security and setup notes.

## Bootstrap

Install Flutter, then run:

```bash
cd mobile
flutter pub get
flutter test
flutter run
```

iOS builds require macOS and Xcode. Never commit API keys, signing files, or local platform configuration.

GitHub Actions validates analysis, tests, an Android debug APK, and a no-codesign iOS build. Store releases require separately configured Android and Apple signing credentials. Do not distribute the CI debug APK as a production release.
