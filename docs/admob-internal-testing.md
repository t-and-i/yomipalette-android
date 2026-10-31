# AdMob internal testing / 広告SDKの内部テスト

## Current behavior

- Debug builds use Google's official sample banner unit.
- Normal release builds (including normal Play internal-test builds) use the production banner unit.
- For a **dedicated QA-only release build**, add `--dart-define=YOMIPALETTE_TEST_ADS=true` to use the official sample unit. This flag must not be used for general production distribution.
- `--dart-define=YOMIPALETTE_AD_DIAGNOSTICS=true` enables detailed SDK/consent/banner diagnostic messages in a release build. Avoid leaving this on in a production release.
- Paid users who have the `remove_ads` entitlement do not mount the banner widget.

## Emulator debug verification

```powershell
flutter build apk --debug
adb devices
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb logcat -c
adb shell am start -n com.tjsongwei.tts_text_mp3_mobile/.MainActivity
adb logcat -v time | Select-String 'YomiPaletteAds|Ads|Consent|UserMessagingPlatform'
```

Look for `Google Mobile Ads SDK initialized`, `Requesting TEST banner`, and `Banner loaded`. An actual `Banner loaded` message plus a visible Google test banner are required to confirm a successful render; `This request is sent from a test device` alone confirms only a test request.

## Play internal testing

Prepare an **upload-signed** AAB for a separate QA-only internal test deployment, retaining the original upload key, app ID and package ID. The existing `scripts/build-play.ps1` invokes Flutter without test flags, so it always creates a normal production-ad AAB. For a QA-only Play build, the build script must explicitly pass both defines to `flutter build appbundle --release` while preserving its signature checks. Do not upload an unsigned or debug-signed AAB. After QA, build a new normal release AAB without those flags and increment versionCode before the next Play upload.

For a test of actual production ad delivery instead, keep the production ad unit, register the physical test device in AdMob first, and check its test status before requesting ads. Google Play's internal testing track does not by itself switch production ads to test mode.

Test on a Play-installed build with a tester account, inspect `adb logcat` for UMP initialization, loaded/failed callbacks and response ID, and verify the test banner visually. If the ad fails, record `code`, `domain`, `message` and relevant response details. Review consent behavior in affected regions and verify the `remove_ads` purchase path separately.
