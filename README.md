# YomiPalette Android

Turn your digital books into audio, with your choice of voice.

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

## 日本語

YomiPalette Androidは、TXT・EPUB・テキスト入りPDFを読み上げ、MP3に変換するAndroidアプリです。章ごと・指定文字数ごとの分割、音声の試聴、保存先フォルダーの選択、音声ファイルの共有に対応しています。Edge TTS、Azure Speech、Google Cloud TTS、Android端末のTTSエンジンを利用でき、画面は日本語・英語・簡体字中国語に切り替えられます。

使い方、対応形式、制限、開発環境については、[日本語の説明全文](README.ja.md)をご覧ください。

## 简体中文

YomiPalette Android是一款将TXT、EPUB及含文本的PDF朗读并转换为MP3的Android应用。支持按章节或指定字符数拆分、语音试听、选择输出文件夹及分享音频。可使用Edge TTS、Azure Speech、Google Cloud TTS及Android设备上的TTS引擎，界面支持日语、英语和简体中文。

使用方法、支持的格式、功能限制及开发环境，请参阅[简体中文完整说明](README.zh-CN.md)。

## English

Android Flutter client for YomiPalette, maintained in **yomipalette-android**. The Windows/macOS app is maintained in [yomipalette-desktop](https://github.com/t-and-i/yomipalette-desktop). iOS development has ended; this repository targets Android only.

## Initial scope

- TXT, EPUB and PDF input. TXT supports automatic detection and manual selection of UTF-8, UTF-16, UTF-32, CP932/Shift_JIS, GB18030, and Big5
- Split by chapter or character limit (default: 5000)
- Approximately 15-second preview from the selected unit, or the first unit
- Edge TTS, Azure Speech, Google Cloud TTS, and installed Android TTS engines
- Credentials stored in Android Keystore or kept for the session only
- MP3 generation, app-document storage, and system sharing
- Direct output to a user-selected folder, with persisted Android folder permission
- Resume from the first unfinished unit after a quota or network failure
- English, Japanese, and Simplified Chinese UI

MOBI, AZW, and AZW3 (Kindle) input is **not supported on mobile** at this time. The desktop version reads them via the `mobi` Python package (KF8 EPUB is reused for AZW3 chapter splits). On mobile, use the desktop build, or pre-convert Kindle files to EPUB with Calibre before importing.

TXT encoding defaults to automatic detection. If the result is incorrect, select an encoding in the TXT character-encoding field to reload the original file bytes. Encoding detection cannot be perfect for every legacy file. EPUB processing is unaffected.

Select an output folder to save there directly. If no folder is selected, files are created in app storage and shared; after the share sheet closes, the app asks whether to delete the current app copies. Kept copies are removed when the app is uninstalled or its data is cleared.

## Unsupported features and reasons

- **Google service-account JSON:** not accepted because it contains a reusable private key. Secure storage protects data at rest but cannot guarantee protection while a rooted/jailbroken device or runtime hook observes the app using it. Google mobile support is API-key-only.
- **OpenAI:** deferred because OpenAI advises against exposing secret API keys in client-side apps. Android Keystore does not eliminate runtime extraction. It can be reconsidered with a backend relay.
- **Edge TTS:** available without an API key. It uses the same unofficial Microsoft Edge Read Aloud service family as the desktop provider, not a supported public Flutter SDK, so a service-side protocol change can break it without notice. Use Azure Speech where a supported service contract is required.
- **Android device TTS:** Android only. The app lists enabled TTS engines and their available voices instead of requiring Samsung TTS specifically. Language data may need to be installed in Android settings. Device synthesis is converted from 16-bit PCM WAV to MP3 with the bundled LAME encoder; engines that return another file format are reported as unsupported.

These restrictions apply only to the mobile project. Desktop providers remain unchanged. See [the Japanese README](README.ja.md) for the complete security and setup notes.

## Bootstrap

Install Flutter 3.47 or later (Dart 3.13 or later), then run:

```bash
cd yomipalette-android
flutter pub get
flutter test
flutter run
```

Install the Android SDK and satisfy the Android requirements reported by `flutter doctor`. Never commit API keys, signing files, or local platform configuration.

GitHub Actions validates analysis, tests, and an Android debug APK. Pushing a new `v*` tag builds a release-mode APK and publishes it to this repository. The current release build uses debug signing and is for testing; production distribution and Google Play require separately configured release signing. No Apple toolchain is required.

## Support YomiPalette

If YomiPalette is useful to you, consider supporting its continued development. Your support helps improve features, fix bugs, and test Windows and Android compatibility. Support is optional and does not change which app features you can use.

- [Support via GitHub Sponsors](https://github.com/sponsors/tjsongwei)
- [Support via Buy Me a Coffee](https://buymeacoffee.com/tjsongweic)

## PDF input

PDFs with embedded text are supported. **By chapter / page** creates units such as `Page 001` in physical page order; **By character count** joins all extracted page text before splitting. PDF bookmarks are not used as chapter boundaries. Pages without text (blank or image-only) are skipped, preserving original page numbers in titles.

OCR is not supported. Image-only/scanned PDFs cannot be read; mixed documents contribute only their text pages. PDFs requiring a password are not supported. Vertical text, columns, tables, and unusual fonts may produce incorrect reading order or extraction. PDF text is extracted on the device; speech generation follows the normal behavior of the selected TTS provider.

## Repository development

Run `flutter analyze`, `flutter test`, and `flutter build apk --release` from this repository root. EPUB cases and synthetic PDF fixtures are self-contained under `test/fixtures/`; PDF fixtures can be regenerated with `python test/fixtures/pdf/generate.py` after installing `pypdf`. Linux tests skip native PDFium cases; run the tests on Windows or macOS to cover them.

Versions are managed independently in `pubspec.yaml`. The Android application ID and internal Dart package name are preserved for compatibility. Historical combined releases remain in [the desktop repository](https://github.com/t-and-i/yomipalette-desktop/releases). New Android releases will appear [here](https://github.com/t-and-i/yomipalette-android/releases).

## License

Released under the [MIT License](LICENSE). Copyright (c) 2026 YuluEthan.
