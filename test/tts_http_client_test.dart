import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tts_text_mp3_mobile/providers/azure_provider.dart';
import 'package:tts_text_mp3_mobile/providers/google_provider.dart';
import 'package:tts_text_mp3_mobile/providers/tts_provider.dart';
import 'package:tts_text_mp3_mobile/services/tts_http_client.dart';

void main() {
  test('Google retries transient HTTP 429 and accepts Retry-After', () async {
    var requests = 0;
    final delays = <Duration>[];
    final provider = GoogleProvider(
      apiKey: 'secret',
      wait: (delay) async => delays.add(delay),
      client: MockClient((request) async {
        requests++;
        if (requests == 1) {
          return http.Response(
            'rate limited',
            429,
            headers: {'retry-after': '1'},
          );
        }
        return http.Response(
          jsonEncode({
            'audioContent': base64Encode([1, 2, 3]),
          }),
          200,
        );
      }),
    );
    addTearDown(provider.close);
    final audio = await provider.synthesize('text', 'ja-JP-Standard-A');
    expect(audio, [1, 2, 3]);
    expect(requests, 2);
    expect(delays, [const Duration(seconds: 1)]);
  });

  test('Azure retries transient 503 while listing voices', () async {
    var attempts = 0;
    final provider = AzureProvider(
      key: 'secret',
      region: 'japaneast',
      wait: (_) async {},
      client: MockClient((_) async {
        attempts++;
        if (attempts == 1) return http.Response('temporary', 503);
        return http.Response(
          jsonEncode([
            {'ShortName': 'ja-JP-NanamiNeural', 'Locale': 'ja-JP'},
          ]),
          200,
        );
      }),
    );
    addTearDown(provider.close);
    expect((await provider.listVoices()).single.locale, 'ja-JP');
    expect(attempts, 2);
  });

  test('authentication errors are not retried', () async {
    var count = 0;
    final provider = GoogleProvider(
      apiKey: 'secret',
      wait: (_) async {},
      client: MockClient((_) async {
        count++;
        return http.Response('invalid key', 401);
      }),
    );
    addTearDown(provider.close);
    await expectLater(
      provider.listVoices(),
      throwsA(isA<TtsProviderException>()),
    );
    expect(count, 1);
  });

  test('transient errors stop after bounded attempts', () async {
    var count = 0;
    final client = TtsHttpClient(
      maxRetries: 2,
      wait: (_) async {},
      client: MockClient((_) async {
        count++;
        return http.Response('unavailable', 503);
      }),
    );
    addTearDown(client.close);
    final response = await client.get(Uri.https('example.test', '/voice'));
    expect(response.statusCode, 503);
    expect(count, 3);
  });

  test('POST transport timeout is not retried and reveals no keys', () async {
    var attempts = 0;
    final provider = GoogleProvider(
      apiKey: 'super-secret-key',
      requestTimeout: const Duration(milliseconds: 10),
      maxRetries: 3,
      wait: (_) async {},
      client: MockClient((_) async {
        attempts++;
        await Future<void>.delayed(const Duration(milliseconds: 90));
        return http.Response('{}', 200);
      }),
    );
    addTearDown(provider.close);
    await expectLater(
      provider.synthesize('test', 'ja-JP-Standard-A'),
      throwsA(
        isA<TtsProviderException>().having(
          (error) => error.toString(),
          'error',
          allOf(contains('timed out'), isNot(contains('super-secret-key'))),
        ),
      ),
    );
    expect(attempts, 1);
  });

  test('failed POST network call is not replayed automatically', () async {
    var attempts = 0;
    final client = TtsHttpClient(
      maxRetries: 2,
      wait: (_) async {},
      client: MockClient((_) async {
        attempts++;
        throw http.ClientException('Connection reset');
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.post(Uri.https('example.test', '/synthesize'), body: 'text'),
      throwsA(isA<TtsProviderException>()),
    );
    expect(attempts, 1);
  });

  test('voice-list GET may retry a transient network exception', () async {
    var attempts = 0;
    final client = TtsHttpClient(
      maxRetries: 2,
      wait: (_) async {},
      client: MockClient((_) async {
        attempts++;
        if (attempts == 1) throw http.ClientException('Connection reset');
        return http.Response('ok', 200);
      }),
    );
    addTearDown(client.close);
    expect((await client.get(Uri.https('example.test', '/voices'))).body, 'ok');
    expect(attempts, 2);
  });
}
