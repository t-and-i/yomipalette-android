import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'tts_provider.dart';

class GoogleProvider implements TtsProvider {
  GoogleProvider({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  Uri _uri(String path) =>
      Uri.https('texttospeech.googleapis.com', path, {'key': apiKey});

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
    final isChirp3Hd = voice.toLowerCase().contains('-chirp3-hd-');
    final audioConfig = <String, dynamic>{
      'audioEncoding': 'MP3',
      'speakingRate': rate.clamp(0.25, 2.0),
      // Chirp 3 HD uses its own voice controls. Do not send the legacy
      // pitch or volume-gain options, even when they are zero.
      if (!isChirp3Hd) ...{
        'volumeGainDb': volume.clamp(-32.0, 16.0),
        'pitch': pitch.clamp(-20.0, 20.0),
      },
    };

    final response = await _client.post(
      _uri('/v1/text:synthesize'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'input': {'text': text},
        'voice': {'name': voice, 'languageCode': _localeFromVoice(voice)},
        'audioConfig': audioConfig,
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
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    // Surface Google's diagnostic code/message without leaking credentials
    // or showing complete HTTP requests (which include the key in the URL).
    String? status;
    String? message;
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['error'] is Map) {
        final error = body['error'] as Map;
        status = error['status'] is String ? error['status'] as String : null;
        message = error['message'] is String
            ? error['message'] as String
            : null;
      }
    } catch (_) {
      // Non-JSON failures retain a safe generic error.
    }
    String safeMessage =
        message ??
        'Check the voice settings and Cloud Text-to-Speech configuration.';
    if (apiKey.isNotEmpty) {
      safeMessage = safeMessage.replaceAll(apiKey, '[redacted]');
    }
    safeMessage = safeMessage.replaceAll(
      RegExp(r'AIza[0-9A-Za-z_-]{20,}'),
      '[redacted]',
    );
    safeMessage = safeMessage.replaceAll(
      RegExp(r'key=[^&\s]+', caseSensitive: false),
      'key=[redacted]',
    );
    if (safeMessage.length > 400) {
      safeMessage = '${safeMessage.substring(0, 400)}…';
    }
    final statusText = status == null || status.isEmpty ? '' : ' [$status]';
    throw TtsProviderException(
      'Google Cloud TTS (${response.statusCode})$statusText: $safeMessage',
    );
  }
}
