# Google Cloud TTS multi-chunk MP3 — Android native QA

This regression test exercises the **GoogleProvider multi-segment output pipeline**, including native Android `flutter_lame` encoding and subsequent `audio_decode` decoding.

It requires **no Google Cloud API key, Google Play purchase, or chargeable request**. The test synthesizes two simple original sine wave tones in memory, encodes them as independent MP3 files, uses a mocked Google Cloud TTS HTTP client to return them, then invokes `AudioGenerator.generateAll` (which uses `Mp3JoinSession` for Google multi-chunk output). The resulting MP3 must decode as one continuous audio stream containing both input segments.

## Run on an authorized Android USB device

Use only the side-by-side QA application package; never replace the Google Play package.

```powershell
cd C:\CodexWorkspace\yomipalette-android
adb devices
$env:ORG_GRADLE_PROJECT_YOMIPALETTE_SIDE_BY_SIDE_QA='true'
try {
  flutter test --no-pub -d R5CT40GL3PY integration_test/google_mp3_join_test.dart
} finally {
  Remove-Item Env:ORG_GRADLE_PROJECT_YOMIPALETTE_SIDE_BY_SIDE_QA -ErrorAction SilentlyContinue
}
```

The test is located in `integration_test/google_mp3_join_test.dart` and runs on-device, not in the Dart VM. It uses synthetic audio created at runtime, so no private audio data or binary test fixture is included in the release APK. `integration_test` is a Flutter SDK **development dependency only**.

## Results

- 2026-11-04, Galaxy SCG14, Android 16: **PASS**.
- The native LAME encoder produced two standalone test MP3 segments; GoogleProvider's mock responses were processed as multiple chunks; the joined MP3 decoded successfully with a consistent sample rate/channels and a duration consistent with multiple segments.
- `flutter analyze --no-pub`: no issues.

## What this does not test

The QA app has no Google Cloud TTS API key configured. Consequently this is **not** a live Google Cloud TTS API verification. Actual API voice selection, request authentication, TTS quotas, response audio encoding and cloud billing still require a separate internal test with an authorized key (avoid logging or committing it).

The Google Play Billing verification backend and RTDN/voided-purchase handling are separate production-release blockers.
