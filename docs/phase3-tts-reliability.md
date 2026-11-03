# Phase 3 — long-form TTS reliability and bounded resource usage

## Scope

- Long MP3 generation no longer retains all synthesized audio clips in memory. The generator writes each completed clip into a per-output-unit staging file before requesting the next clip.
- For Google Cloud TTS with multiple MP3 segments, a single LAME encoder session incrementally decodes/re-encodes each segment into a continuous MP3 stream. The one-segment case keeps the original MP3 bytes. For Edge/Azure/device TTS the existing concatenation behavior is preserved.
- The preview API (`synthesizeLong`) remains in-memory because preview input is intentionally short. Other TTS services that return a complete synthesized clip at once also necessarily hold that individual clip in memory.
- For Android's Storage Access Framework, a complete MP3 is staged on app-private storage, then read once and sent via the existing method channel to `SafeDocumentWriter`. This **still requires memory proportional to the final MP3**, but avoids holding all the individual clips *plus* PCM and the final file simultaneously. Removing that final copy requires a separate native streaming file-write API.
- For local filesystem destinations, staging occurs under the target directory and the complete file is published only after the entire chapter succeeds. Existing MP3s are moved to a recoverable backup during replacement. The staging directory is removed on success, exception, or cancellation.

## Cancellation and resume

- While an MP3 is generating, the action button becomes **Cancel generation** (Japanese: 生成をキャンセル / Chinese: 取消生成).
- Cancellation is cooperative between chunks and just before publication. An ongoing platform/cloud request cannot be aborted immediately and may finish or time out before cancellation takes effect.
- A partially synthesized chapter is never published; previously completed MP3s stay intact. The existing per-unit selection/resume behavior is preserved, so users can continue with unfinished units.
- **Resume is by output unit, not by partially synthesized chunk.** On resume, an interrupted unit starts from its first chunk to avoid assembling mismatched audio/settings.
- Cancelling after one output is completed does not remove that output. New temp files and the staged unfinished output are deleted.

## Cloud transport and cost controls

- Azure Speech and Google Cloud TTS have a 60-second per-request timeout. Provider-owned HTTP clients are explicitly closed when their UI operation completes. Callers supplying external test clients retain ownership.
- Only HTTP **429, 502, 503, 504** are retried automatically, up to two retries (three total attempts), with bounded backoff / short Retry-After handling.
- Voice-list GET requests may retry temporary socket/client errors. **POST synthesis requests never automatically retry network exceptions or timeouts** because a dropped response can represent a completed and chargeable synthesis operation. HTTP 400/401/403 and other permanent failures are not retried.
- Some HTTP transient response retries can still result in extra billable requests; the user should review their cloud billing quotas and limits. This behavior does not bypass any provider quotas or authentication rules.
- Google API keys and Azure subscription secrets must never be included in timeout/network errors.

## Compatibility and verification

- No Google Play Billing, AdMob, package ID, versionCode, provider-selection preference key, or signing change.
- MP3 naming and output directory IDs are unchanged.
- Tests cover timeouts, status retries, no retry on authentication errors, single retry per bounded failure, incremental output, old file preservation, cancellation, app-like SAF file-writer behavior, cleanup and UI cancellation labels.
- Run `flutter analyze --no-pub` and `flutter test --no-pub`. For Android, use the existing side-by-side `.qa` debug app and a test-only folder. Never overwrite the Play version's data.

## Follow-up

- True end-to-end streaming into SAF (rather than sending one finished byte array through MethodChannel) is a separate Android platform-channel project.
- TTS service-side synthesis charges are outside the app's control.
- Google Cloud multiple-chunk audio continuity uses an Android native MP3 encoder; test native encoding on a device with a Google Cloud TTS test configuration before promoting to production.
- Phase 1's server-side Play Billing token verification remains an independent blocker before public release.


## Device QA evidence (November 4, 2026)

- Galaxy SCG14 / Android 16, USB ADB, isolated `com.tjsongwei.tts_text_mp3_mobile.qa` debug build. Original Play app and data were not replaced.
- Test-only directory: `Download/YomiPalette-QA`. Device TTS with Google speech synthesis engine.
- `phase3_long.txt` (1,926 characters): generated `001_phase3_long.mp3`, 240,384 bytes, duration 15.024 seconds, 24 kHz mono. FFmpeg decode exit code 0.
- `phase3_cancel.txt` (3,772 characters): tapping **Cancel generation** showed the expected Japanese cancellation status, kept the unfinished MP3 unpublished and changed the button to **Continue generation**. Resuming generated `001_phase3_cancel.mp3`, 125,568 bytes, 7.848 seconds; FFmpeg decode exit code 0.
- Previously generated `001_qa_phase1.mp3` remained present and unchanged in file size (146,304 bytes). No staging or backup files remained in the test directory.
- These checks verify device-TTS multi-chunk streaming and cancel/resume. They do NOT substitute for a dedicated Google Cloud TTS multi-chunk native MP3-join integration test.
