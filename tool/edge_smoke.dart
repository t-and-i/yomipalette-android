import 'dart:io';

import 'package:tts_text_mp3_mobile/providers/edge_provider.dart';

Future<void> main() async {
  final provider = EdgeProvider();
  final voices = await provider.listVoices();
  final voice = voices.firstWhere(
    (item) => item.name == 'ja-JP-NanamiNeural',
    orElse: () => voices.first,
  );
  final audio = await provider.synthesize('Edge TTSの動作確認です。', voice.name);
  if (audio.isEmpty) throw StateError('Edge TTS returned no audio.');
  stdout.writeln('Edge TTS OK: ${voice.name}, ${audio.length} bytes');
}
