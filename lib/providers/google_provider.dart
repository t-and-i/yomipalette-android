import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'tts_provider.dart';

class GoogleProvider implements TtsProvider {
  GoogleProvider({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  Uri _uri(String path) => Uri.https(
        'texttospeech.googleapis.com',
        path,
        {'key': apiKey},
      );

  @override
  Future<List<VoiceInfo>> listVoices() async {
    final response = await _client.get(_uri('/v1/voices'));
    _ensureSuccess(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final voices = body['voices'] as List<dynamic>? ?? const [];
    return voices.map((value) {
      final item = value as Map<String, dynamic>;
      final codes = item['languageCodes'] as List<dynamic>? ?? const [];
      return VoiceInfo(
        name: item['name'] as String,
        locale: codes.isEmpty ? '' : codes.first as String,
        gender: item['ssmlGender'] as String? ?? '',
      );
    }).toList();
  }

  @override
  Future<Uint8List> synthesize(
    String text,
    String voice, {
    double rate = 1,
    double volume = 0,
    double pitch = 0,
  }) async {
    final response = await _client.post(
      _uri('/v1/text:synthesize'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'input': {'text': text},
        'voice': {'name': voice, 'languageCode': _localeFromVoice(voice)},
        'audioConfig': {
          'audioEncoding': 'MP3',
          'speakingRate': rate.clamp(.25, 4),
          'volumeGainDb': volume.clamp(-32, 16),
          'pitch': pitch.clamp(-20, 20),
        },
      }),
    );
    _ensureSuccess(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return base64Decode(body['audioContent'] as String);
  }

  String _localeFromVoice(String voice) {
    final parts = voice.split('-');
    return parts.length >= 2 ? '${parts[0]}-${parts[1]}' : 'en-US';
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TtsProviderException(
        'Google request failed (${response.statusCode}). Enable Cloud Text-to-Speech and check API key restrictions.',
      );
    }
  }
}
