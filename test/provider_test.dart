import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tts_text_mp3_mobile/providers/azure_provider.dart';
import 'package:tts_text_mp3_mobile/providers/google_provider.dart';

void main() {
  test('Azure sends the key only in the subscription header', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'japaneast.tts.speech.microsoft.com');
      expect(request.url.query, isEmpty);
      expect(request.headers['Ocp-Apim-Subscription-Key'], 'secret');
      return http.Response(
        jsonEncode([
          {'ShortName': 'ja-JP-NanamiNeural', 'Locale': 'ja-JP'}
        ]),
        200,
      );
    });
    final provider = AzureProvider(
      key: 'secret',
      region: 'japaneast',
      client: client,
    );
    final voices = await provider.listVoices();
    expect(voices.single.name, 'ja-JP-NanamiNeural');
  });

  test('Google decodes MP3 content returned by the REST API', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['key'], 'user-key');
      expect(request.url.path, '/v1/text:synthesize');
      return http.Response(
          jsonEncode({
            'audioContent': base64Encode([1, 2, 3])
          }),
          200);
    });
    final provider = GoogleProvider(apiKey: 'user-key', client: client);
    final audio = await provider.synthesize('hello', 'en-US-Neural2-A');
    expect(audio, [1, 2, 3]);
  });
}
