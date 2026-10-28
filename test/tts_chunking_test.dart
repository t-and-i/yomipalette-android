import 'dart:convert';
import 'dart:io';

import 'package:audio_decode/audio_decode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tts_text_mp3_mobile/providers/google_provider.dart';
import 'package:tts_text_mp3_mobile/providers/tts_provider.dart';
import 'package:tts_text_mp3_mobile/services/audio_generator.dart';
import 'package:tts_text_mp3_mobile/services/mp3_joiner.dart';
import 'package:tts_text_mp3_mobile/services/tts_chunking.dart';

void main() {
  test(
    'UTF-8, emoji and Japanese punctuation are preserved when splitting',
    () {
      const text =
          'あいうえお。'
          '😀'
          'かきくけこ、'
          'さしすせそ。';
      final chunks = splitTtsText(
        text,
        const TtsChunkPolicy(maxChars: 7, maxUtf8Bytes: 18),
      );
      expect(chunks.join(), text);
      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.runes.length, lessThanOrEqualTo(7));
        expect(utf8.encode(chunk).length, lessThanOrEqualTo(18));
      }
    },
  );

  test('model-based limits are stricter for Chirp 3 HD', () {
    final chirp = TtsChunkPolicy.forVoice('google', 'ja-JP-Chirp3-HD-Achernar');
    final standard = TtsChunkPolicy.forVoice('google', 'ja-JP-Standard-A');
    expect(chirp.maxChars, lessThan(standard.maxChars));
    expect(splitTtsText('あ' * 200, chirp).length, greaterThan(1));
    expect(splitTtsText('あ' * 200, standard), hasLength(1));
  });

  test('only long-sentence failures are retried', () {
    expect(
      isSentenceTooLongError(
        const TtsProviderException(
          'Google Cloud TTS (400) [INVALID_ARGUMENT]: '
          'This request contains sentences that are too long.',
        ),
      ),
      isTrue,
    );
    expect(
      isSentenceTooLongError(
        const TtsProviderException(
          'Google Cloud TTS (403) [PERMISSION_DENIED]: billing inactive.',
        ),
      ),
      isFalse,
    );
  });

  test(
    'multiple independent MP3 clips become one playable MP3',
    () async {
      final clip = await File('test/fixtures/audio/tone.mp3').readAsBytes();
      final joined = await Mp3Joiner.join([clip, clip]);
      final pcm = decodeMp3(joined);
      expect(pcm.frameCount, greaterThan(15000));
      expect(pcm.channels, 1);
      expect(pcm.duration.inMilliseconds, greaterThan(650));
    },
    // LAME is bundled with the Android APK, not with host-side flutter test.
    // Validate native encoding on a device with an Android integration test.
    skip: !Platform.isAndroid
        ? 'Native MP3 encoder is packaged with Android; not available in desktop test runners.'
        : null,
  );

  test(
    'Google long sentence is split and re-tried within a bounded budget',
    () async {
      final clip = await File('test/fixtures/audio/tone.mp3').readAsBytes();
      final sent = 'あ' * 70;
      var calls = 0;
      final reports = <(int, int, bool)>[];
      final provider = GoogleProvider(
        apiKey: 'test-key',
        client: MockClient((request) async {
          calls++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final input = (body['input'] as Map)['text'] as String;
          if (input.runes.length > 30) {
            return http.Response(
              jsonEncode({
                'error': {
                  'code': 400,
                  'status': 'INVALID_ARGUMENT',
                  'message':
                      'This request contains sentences that are too long.',
                },
              }),
              400,
            );
          }
          return http.Response(
            jsonEncode({'audioContent': base64Encode(clip)}),
            200,
          );
        }),
      );
      final audio = await AudioGenerator.synthesizeLong(
        provider,
        sent,
        'ja-JP-Chirp3-HD-Achernar',
        mp3Joiner: (clips) async {
          expect(clips.length, greaterThan(1));
          return clips.first;
        },
        onChunkProgress: (done, total, retrying) {
          reports.add((done, total, retrying));
        },
      );
      expect(calls, greaterThan(2));
      expect(calls, lessThan(32));
      expect(reports.any((entry) => entry.$3), isTrue);
      expect(reports.last.$1, reports.last.$2);
      expect(audio, clip);
    },
  );

  test('invalid billing status is never recursively retried', () async {
    var calls = 0;
    final provider = GoogleProvider(
      apiKey: 'test-key',
      client: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'error': {
              'code': 403,
              'status': 'PERMISSION_DENIED',
              'message': 'Not permitted for this project',
            },
          }),
          403,
        );
      }),
    );
    await expectLater(
      AudioGenerator.synthesizeLong(
        provider,
        'あ' * 90,
        'ja-JP-Chirp3-HD-Achernar',
      ),
      throwsA(isA<TtsProviderException>()),
    );
    expect(calls, 1);
  });

  test('auto split can be disabled', () async {
    var calls = 0;
    final provider = GoogleProvider(
      apiKey: 'test-key',
      client: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'audioContent': base64Encode([1]),
          }),
          200,
        );
      }),
    );
    await AudioGenerator.synthesizeLong(
      provider,
      'あ' * 300,
      'ja-JP-Chirp3-HD-Achernar',
      autoSplit: false,
    );
    expect(calls, 1);
  });
}
