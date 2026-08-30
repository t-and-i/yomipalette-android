import 'dart:typed_data';

import 'package:flutter_edge_tts/flutter_edge_tts.dart';

import 'tts_provider.dart';

/// API-key-free Edge Read Aloud provider.
///
/// The endpoint is not a supported public Microsoft API and may change without
/// notice. The package owns the DRM and websocket compatibility layer so it can
/// be updated independently of this app.
class EdgeProvider implements TtsProvider {
  static const _defaultVoice = 'en-US-EmmaMultilingualNeural';

  @override
  Future<List<VoiceInfo>> listVoices() async {
    final client = FlutterEdgeTts(voice: _defaultVoice);
    try {
      final voices = await client.getVoices();
      return voices
          .map((voice) => VoiceInfo(
                name: voice.shortName,
                locale: voice.locale,
                gender: voice.gender,
              ))
          .toList(growable: false);
    } finally {
      await client.close();
    }
  }

  @override
  Future<Uint8List> synthesize(
    String text,
    String voice, {
    double rate = 1,
    double volume = 0,
    double pitch = 0,
  }) async {
    final client = FlutterEdgeTts(
      voice: voice,
      outputFormat: EdgeTtsOutputFormat.audio24Khz48KbitrateMonoMp3,
    );
    try {
      final result = await client.synthesize(
        text,
        prosody: EdgeTtsProsody(
          rate: rate.toStringAsFixed(2),
          volume: (100 + volume).clamp(0, 100).round().toString(),
          pitch: '${pitch >= 0 ? '+' : ''}${pitch.round()}Hz',
        ),
      );
      return result.audioBytes;
    } finally {
      await client.close();
    }
  }
}
