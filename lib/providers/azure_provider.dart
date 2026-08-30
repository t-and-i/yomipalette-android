import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'tts_provider.dart';

class AzureProvider implements TtsProvider {
  AzureProvider({required this.key, required this.region, http.Client? client})
      : _client = client ?? http.Client();

  final String key;
  final String region;
  final http.Client _client;

  Uri _uri(String path) => Uri.https('$region.tts.speech.microsoft.com', path);

  Map<String, String> get _headers => {'Ocp-Apim-Subscription-Key': key};

  @override
  Future<List<VoiceInfo>> listVoices() async {
    final response = await _client.get(
      _uri('/cognitiveservices/voices/list'),
      headers: _headers,
    );
    _ensureSuccess(response);
    final values = jsonDecode(response.body) as List<dynamic>;
    return values.map((value) {
      final item = value as Map<String, dynamic>;
      return VoiceInfo(
        name: item['ShortName'] as String,
        locale: item['Locale'] as String? ?? '',
        gender: item['Gender'] as String? ?? '',
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
    final language = voice.split('-').take(2).join('-');
    final escaped = const HtmlEscape(HtmlEscapeMode.element).convert(text);
    final ratePercent = ((rate - 1) * 100).round();
    final volumePercent = volume.round();
    final pitchHz = pitch.round();
    final signedRate = '${ratePercent >= 0 ? '+' : ''}$ratePercent%';
    final signedVolume = '${volumePercent >= 0 ? '+' : ''}$volumePercent%';
    final signedPitch = '${pitchHz >= 0 ? '+' : ''}${pitchHz}Hz';
    final ssml =
        '''<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="$language"><voice name="$voice"><prosody rate="$signedRate" volume="$signedVolume" pitch="$signedPitch">$escaped</prosody></voice></speak>''';
    final response = await _client.post(
      _uri('/cognitiveservices/v1'),
      headers: {
        ..._headers,
        'Content-Type': 'application/ssml+xml',
        'X-Microsoft-OutputFormat': 'audio-24khz-48kbitrate-mono-mp3',
        'User-Agent': 'tts-text-mp3-mobile',
      },
      body: utf8.encode(ssml),
    );
    _ensureSuccess(response);
    return response.bodyBytes;
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TtsProviderException(
        'Azure request failed (${response.statusCode}). Check the key and region.',
      );
    }
  }
}
