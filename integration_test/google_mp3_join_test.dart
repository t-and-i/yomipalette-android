import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';
import 'package:flutter_lame/flutter_lame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tts_text_mp3_mobile/models/chapter.dart';
import 'package:tts_text_mp3_mobile/providers/google_provider.dart';
import 'package:tts_text_mp3_mobile/services/audio_generator.dart';

/// Tests the Google Cloud multi-MP3 code path on a real Android device with
/// two original synthetic tones, using no paid Google API or private audio.
///
/// The test runs GoogleProvider -> AudioGenerator -> Mp3JoinSession ->
/// native Android LAME encoding -> audio_decode decoding.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Google multi-chunk output is decodable on Android', (
    tester,
  ) async {
    const sampleRate = 24000;
    Future<Uint8List> makeTone(int frequency) async {
      final pcm = Int16List(sampleRate);
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = (math.sin(2 * math.pi * frequency * i / sampleRate) * 16384)
            .round();
      }
      final encoder = LameMp3Encoder(
        sampleRate: sampleRate,
        numChannels: 1,
        bitRate: 128,
      );
      try {
        final result = BytesBuilder(copy: false);
        result.add(await encoder.encode(leftChannel: pcm));
        result.add(await encoder.flush());
        return result.takeBytes();
      } finally {
        await encoder.close();
      }
    }

    final a = await makeTone(440);
    final b = await makeTone(660);
    final pcmA = decodeMp3(a);
    final pcmB = decodeMp3(b);
    expect(pcmA.frameCount, greaterThan(0));
    expect(pcmB.frameCount, greaterThan(0));

    var requests = 0;
    final provider = GoogleProvider(
      apiKey: 'fixture-only-not-a-real-key',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, contains('text:synthesize'));
        requests++;
        final clip = requests.isOdd ? a : b;
        return http.Response(
          jsonEncode({'audioContent': base64Encode(clip)}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final completedFiles = <String, Uint8List>{};
    try {
      final paths = await AudioGenerator.generateAll(
        provider,
        [
          Chapter(
            index: 1,
            title: 'native-join-fixture',
            text: 'Hello. ' * 700,
          ),
        ],
        'en-US-Standard-A',
        fileWriter: (name, bytes) async {
          completedFiles[name] = bytes;
          return 'content://phase3-qa/$name';
        },
      );
      expect(requests, greaterThanOrEqualTo(2));
      expect(paths, hasLength(1));
      expect(completedFiles, hasLength(1));

      final combined = completedFiles.values.single;
      expect(combined.length, greaterThan(1000));
      final result = decodeMp3(combined);
      expect(result.sampleRate, pcmA.sampleRate);
      expect(result.channels, pcmA.channels);
      expect(
        result.frameCount,
        greaterThan(pcmA.frameCount + pcmB.frameCount - 6000),
      );
    } finally {
      provider.close();
    }
  });
}
