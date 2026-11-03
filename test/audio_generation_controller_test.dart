import 'package:flutter_test/flutter_test.dart';
import 'package:tts_text_mp3_mobile/controllers/audio_generation_controller.dart';
import 'package:tts_text_mp3_mobile/services/preview_audio_player.dart';

class _FakePlayer implements PreviewAudioPlayer {
  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<void> setFilePath(String path) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seekToStart() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  test('reset clears generation resume state and generated file tracking', () {
    final controller = AudioGenerationController(player: _FakePlayer());
    controller.generatedPaths.addAll(['one.mp3', 'two.mp3']);
    controller.resumeIndex = 1;

    controller.reset();

    expect(controller.generatedPaths, isEmpty);
    expect(controller.resumeIndex, isNull);
  });
}
