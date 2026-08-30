# TTS Text to MP3 Mobile

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

Flutter client for Android and iOS, maintained as a separate project under `mobile/` in the desktop repository.

## Initial scope

- TXT and EPUB input
- Split by chapter or character limit (default: 5000)
- Approximately 15-second preview from the selected unit, or the first unit
- Azure Speech and Google Cloud TTS API-key authentication
- Credentials stored in Android Keystore/iOS Keychain or kept for the session only
- MP3 generation, app-document storage, and system sharing
- English, Japanese, and Simplified Chinese UI

## Unsupported features and reasons

- **Google service-account JSON:** not accepted because it contains a reusable private key. Secure storage protects data at rest but cannot guarantee protection while a rooted/jailbroken device or runtime hook observes the app using it. Google mobile support is API-key-only.
- **OpenAI:** deferred because OpenAI advises against exposing secret API keys in client-side apps. Keystore/Keychain does not eliminate runtime extraction. It can be reconsidered with a backend relay.
- **Edge TTS:** deferred because the desktop implementation depends on the Python `edge-tts` package and there is no equivalent supported Flutter/Dart SDK with the same contract.

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
