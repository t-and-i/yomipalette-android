# AGENTS.md

## Project
- YomiPalette Android is a standalone Flutter app. Run commands from the repository root.
- `lib/` contains UI, localization, providers, and document/audio services; `android/` contains the host project. iOS development has ended; do not recreate an iOS host.
- Windows/macOS development lives at https://github.com/t-and-i/yomipalette-desktop.
- Flutter >= 3.47 and Dart >= 3.13 are required. Preserve the internal package name `tts_text_mp3_mobile`, Android namespace/applicationId `com.tjsongwei.tts_text_mp3_mobile`, and persisted settings/credential keys.
- Versions are managed independently in `pubspec.yaml`; do not bump them unless requested.

## Checks
- Run `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter build apk --release`.
- Synthetic EPUB/PDF fixtures live in `test/fixtures/`. PDF regeneration: `python test/fixtures/pdf/generate.py` (requires pypdf). Linux skips native PDFium tests; use a Windows/macOS host for those cases.
- Keep TXT/EPUB/PDF imports and the `['txt', 'epub', 'pdf']` extension allowlist. Kindle formats remain desktop-only.
- Update Japanese, English, and Simplified Chinese strings together in `lib/l10n/strings.dart`.
- Preserve chapter boundaries, selectable units, output resume behavior, Android folder permissions, and TTS settings.

## Credentials and releases
- Never commit API keys, credentials, local.properties, signing keys, or build outputs. Keep the Android secure-storage behavior and provider contracts.
- `LICENSE` and `.github/FUNDING.yml` apply to this project; retain GitHub Sponsors before Buy Me a Coffee.
- `.github/workflows/android.yml` validates pushes/PRs. `.github/workflows/release.yml` builds APKs and publishes only for new `v*` tags.
- Current release-mode APKs use debug signing. Production/Play signing is separate work.
- Do not create tags, publish releases, or change signing without authorization.
