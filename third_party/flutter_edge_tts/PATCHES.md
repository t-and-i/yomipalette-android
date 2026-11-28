# Local patch for RA-05

Based on flutter_edge_tts 0.0.3 from pub.dev. Original LICENSE, NOTICE and
LICENSES are retained alongside the source.

The upstream stream closes successfully when its WebSocket closes, including
before `Path:turn.end`. Its byte accumulator then returns partial MP3 data as
a successful result. The local change requires that completion message and
emits `EdgeTtsException(incomplete_audio)` on an earlier close. Existing app
staging and resume handling can then retain the unfinished unit for retry.

An optional WebSocket connector allows the app regression test to drive the
real stream parser and synthesis code against a loopback server. Production
continues to use the original endpoint, headers and connection implementation.

Regression command from the repository root

```powershell
flutter test test/edge_interrupted_generation_test.dart
```

The test reproduces partial-file publication before the completion check, then
verifies rejection, staging cleanup, preservation of a completed file and
successful regeneration of the unfinished unit after the patch.
