import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tts_text_mp3_mobile/providers/google_provider.dart';
import 'package:tts_text_mp3_mobile/providers/tts_provider.dart';

void main() {
  final mp3 = Uint8List.fromList([0x49, 0x44, 0x33, 0, 1]);
  http.Response success() =>
      http.Response(jsonEncode({'audioContent': base64Encode(mp3)}), 200);

  test('Standard voice keeps supported voice controls', () async {
    late Map<String, dynamic> payload;
    final provider = GoogleProvider(
      apiKey: 'test-key',
      client: MockClient((request) async {
        expect(request.url.path, '/v1/text:synthesize');
        expect(request.url.queryParameters['key'], 'test-key');
        expect(request.method, 'POST');
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return success();
      }),
    );
    final audio = await provider.synthesize(
      'こんにちは',
      'ja-JP-Standard-A',
      rate: 5,
      volume: 4,
      pitch: -3,
    );
    expect(audio, mp3);
    expect(payload['voice'], {
      'name': 'ja-JP-Standard-A',
      'languageCode': 'ja-JP',
    });
    expect(payload['input'], {'text': 'こんにちは'});
    expect(payload['audioConfig'], {
      'audioEncoding': 'MP3',
      'speakingRate': 2.0,
      'volumeGainDb': 4.0,
      'pitch': -3.0,
    });
  });

  test('Chirp 3 HD omits legacy pitch and gain but supports rate', () async {
    late Map<String, dynamic> payload;
    final provider = GoogleProvider(
      apiKey: 'test-key',
      client: MockClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return success();
      }),
    );
    await provider.synthesize(
      '音声テスト',
      'ja-JP-Chirp3-HD-Achernar',
      rate: 1.3,
      volume: 15,
      pitch: 10,
    );
    expect(payload['audioConfig'], {
      'audioEncoding': 'MP3',
      'speakingRate': 1.3,
    });
  });

  test('Chirp 3 HD with zero adjustments still omits legacy keys', () async {
    late Map<String, dynamic> payload;
    final provider = GoogleProvider(
      apiKey: 'test-key',
      client: MockClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return success();
      }),
    );
    await provider.synthesize('test', 'en-US-Chirp3-HD-Leda');
    final config = payload['audioConfig'] as Map<String, dynamic>;
    expect(config.keys, containsAll(['audioEncoding', 'speakingRate']));
    expect(config, isNot(contains('pitch')));
    expect(config, isNot(contains('volumeGainDb')));
  });

  test('Google errors expose status safely without API key', () async {
    const secret = 'AIzaThisIsASampleKeyForRedaction12345678';
    final provider = GoogleProvider(
      apiKey: secret,
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'error': {
              'code': 400,
              'status': 'INVALID_ARGUMENT',
              'message': 'pitch is unsupported; key=$secret',
            },
          }),
          400,
        ),
      ),
    );
    expect(
      () => provider.synthesize('test', 'ja-JP-Chirp3-HD-Achernar'),
      throwsA(
        isA<TtsProviderException>().having(
          (error) => error.toString(),
          'diagnostic',
          allOf(
            contains('400'),
            contains('INVALID_ARGUMENT'),
            contains('pitch is unsupported'),
            isNot(contains(secret)),
          ),
        ),
      ),
    );
  });

  test('non-JSON Google errors fall back to a generic message', () async {
    final provider = GoogleProvider(
      apiKey: 'test-key',
      client: MockClient(
        (request) async => http.Response('gateway error', 503),
      ),
    );
    expect(
      () => provider.listVoices(),
      throwsA(
        isA<TtsProviderException>().having(
          (error) => error.toString(),
          'diagnostic',
          allOf(contains('503'), isNot(contains('gateway error'))),
        ),
      ),
    );
  });
}
