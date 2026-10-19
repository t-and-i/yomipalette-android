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
- `LICENSE` applies to this project. Do not add donation or sponsorship solicitations to the Android app or its repository documentation.
- `.github/workflows/android.yml` validates pushes/PRs. `.github/workflows/release.yml` builds APKs and publishes only for new `v*` tags.
- Ordinary release-mode APKs use debug signing. Play AABs use scripts/build-play.ps1 with an external upload key; no automatic upload. Never fall back to debug signing for a Play AAB.
- Do not create tags, publish releases, or change signing without authorization.
