import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_text_mp3_mobile/controllers/audio_generation_controller.dart';
import 'package:tts_text_mp3_mobile/models/chapter.dart';
import 'package:tts_text_mp3_mobile/providers/tts_provider.dart';
import 'package:tts_text_mp3_mobile/services/audio_generation_cancellation.dart';
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

class _ClosableProvider implements TtsProvider, ClosableTtsProvider {
  bool closed = false;

  @override
  void close() => closed = true;

  @override
  Future<List<VoiceInfo>> listVoices() async => const [];

  @override
  Future<Uint8List> synthesize(
    String text,
    String voice, {
    double rate = 1,
    double volume = 0,
    double pitch = 0,
  }) async => Uint8List.fromList([1, 2]);
}

void main() {
  test(
    'cancel while provider is preparing prevents file publication',
    () async {
      final directory = await Directory.systemTemp.createTemp('yomi-cancel-');
      addTearDown(() => directory.delete(recursive: true));
      final controller = AudioGenerationController(player: _FakePlayer());
      final provider = _ClosableProvider();

      controller.prepareGeneration();
      expect(controller.canCancel, isTrue);
      controller.cancel();

      await expectLater(
        controller.generate(
          provider: provider,
          units: const [Chapter(index: 1, title: 'test', text: 'hello')],
          voiceName: 'test',
          outputDirectory: directory.path,
          ratePercent: 0,
          volumePercent: 0,
          pitchHz: 0,
          autoSplit: true,
          autoRetry: true,
          onChunkProgress: (_, __, ___, ____, _____) {},
          onProgress: (_, __) {},
          onFileGenerated: (_, __, ___) {},
        ),
        throwsA(isA<AudioGenerationCancelled>()),
      );

      controller.clearPendingGeneration();
      expect(provider.closed, isTrue);
      expect(controller.canCancel, isFalse);
      expect(directory.listSync(), isEmpty);
    },
  );

  test('cancel without active generation does not poison next run', () async {
    final directory = await Directory.systemTemp.createTemp('yomi-idle-');
    addTearDown(() => directory.delete(recursive: true));
    final controller = AudioGenerationController(player: _FakePlayer());
    controller.cancel(); // Idle cancellation must be a no-op.
    final provider = _ClosableProvider();
    final paths = await controller.generate(
      provider: provider,
      units: const [Chapter(index: 1, title: 'test', text: 'hello')],
      voiceName: 'test',
      outputDirectory: directory.path,
      ratePercent: 0,
      volumePercent: 0,
      pitchHz: 0,
      autoSplit: true,
      autoRetry: true,
      onChunkProgress: (_, __, ___, ____, _____) {},
      onProgress: (_, __) {},
      onFileGenerated: (_, __, ___) {},
    );
    expect(paths, hasLength(1));
    expect(provider.closed, isTrue);
  });
}
