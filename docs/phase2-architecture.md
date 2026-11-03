# YomiPalette Phase 2 — UI / controllers separation

## Goal
Move presentation, document state, TTS configuration and audio generation coordination out of the former all-in-one `lib/main.dart`, without changing Google Play configuration, stored preferences, billing or generated MP3 formats.

## Structure

| Path | Responsibility |
|---|---|
| `lib/main.dart` | Application root, theme, locale, Billing controller lifecycle. It re-exports `HomeScreen` for existing integrations/tests. |
| `lib/screens/home_screen.dart` | Screen coordination, file picker, folder picker, dialogs, status updates, lifecycle and callbacks. No longer contains the app root. |
| `lib/controllers/document_controller.dart` | Document data and bytes, encoding/split settings, generated unit selection, file replacement state. |
| `lib/controllers/tts_settings_controller.dart` | TTS provider credentials, voice selection and audio options, provider creation, preserving preference key names. |
| `lib/controllers/audio_generation_controller.dart` | Preview synthesis/playback, MP3 generation request construction, output directory routing and generation progress tracking. |
| `lib/widgets/provider_settings_section.dart` | Provider selector, device engine and credential inputs. |
| `lib/widgets/output_units_section.dart` | Select all/none, per-unit checkboxes and selected unit highlighting. |
| `lib/widgets/audio_adjustment_slider.dart` | Speed/volume/pitch slider rendering. |
| `lib/widgets/ad_free_section.dart` | Display only; Billing authorization stays in `AdFreePurchaseController`. |
| `lib/widgets/generation_actions.dart` | Bottom progress, AdMob banner, preview/stop and MP3 action buttons. |

The screen explicitly calls `setState` for presentation updates; the controllers intentionally do not own `BuildContext` or trigger global application rebuilds.

## Compatibility invariants
- External app entry point is still `TtsMobileApp` in `main.dart`, and `HomeScreen` is re-exported.
- `theme_mode`, `provider`, `text_encoding`, `split_by_chars`, `max_chars`, `device_tts_engine`, `tts_auto_split`, `tts_auto_retry`, `tts_show_progress`, `rate_percent`, `volume_percent`, `pitch_hz`, `output_directory`, `output_directory_label` retain their old SharedPreferences keys.
- The existing Billing verification, AdMob banner and SAF safe replacement semantics are unchanged.
- `appId`, Google Play package name, minSdk, signing, versionCode are unchanged.
- No third-party state-management package is introduced.

## Verification
Run `flutter analyze`, `flutter test`, and for Android `flutter build apk --debug`. The Android `.qa` test variant can be installed alongside the Play application using `ORG_GRADLE_PROJECT_YOMIPALETTE_SIDE_BY_SIDE_QA=true`. Never uninstall the Play version for QA.

The new unit tests verify document selection/splitting, TTS locale and preferences, audio generation state reset, in addition to the existing UI, Billing and audio tests.

## Remaining design opportunities
The `HomeScreen` still coordinates several asynchronous side effects (file/folder picker, permissions, voice list loading). Further splitting should be driven by testable use cases rather than splitting for line count alone. No server-side Billing integration is included in Phase 2; Phase 1's deployment blocker remains.
