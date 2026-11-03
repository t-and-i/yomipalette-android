import 'dart:typed_data';

import '../models/chapter.dart';
import '../providers/tts_provider.dart';
import '../services/audio_generator.dart';
import '../services/output_directory_service.dart';
import '../services/preview_audio_player.dart';
import '../services/text_splitter.dart';

/// Coordinates preview and audio file generation. UI state, progress text,
/// and error presentation remain in the home screen.
class AudioGenerationController {
  AudioGenerationController({required this.player});

  final PreviewAudioPlayer player;
  final List<String> generatedPaths = [];
  int? resumeIndex;

  void reset() {
    resumeIndex = null;
    generatedPaths.clear();
  }

  Future<void> preview({
    required TtsProvider provider,
    required Chapter unit,
    required String voiceName,
    required double ratePercent,
    required double volumePercent,
    required double pitchHz,
    required bool autoSplit,
    required bool autoRetry,
    void Function(int completed, int total, bool retrying)? onChunkProgress,
  }) async {
    final bytes = await AudioGenerator.synthesizeLong(
      provider,
      previewText(unit.text),
      voiceName,
      rate: 1 + ratePercent / 100,
      volume: volumePercent,
      pitch: pitchHz,
      autoSplit: autoSplit,
      retryLongSentences: autoRetry,
      onChunkProgress: onChunkProgress,
    );
    final file = await AudioGenerator.writeTemporary(bytes, 'tts-preview.mp3');
    await player.setFilePath(file);
    await player.play();
  }

  Future<List<String>> generate({
    required TtsProvider provider,
    required List<Chapter> units,
    required String voiceName,
    required String? outputDirectory,
    required double ratePercent,
    required double volumePercent,
    required double pitchHz,
    required bool autoSplit,
    required bool autoRetry,
    required void Function(
      int unit,
      int unitTotal,
      int chunk,
      int chunkTotal,
      bool retrying,
    )
    onChunkProgress,
    required void Function(int current, int total) onProgress,
    required void Function(String path, int current, int total) onFileGenerated,
  }) {
    final documentTree =
        outputDirectory != null &&
        OutputDirectoryService.isAndroidDocumentTree(outputDirectory);
    return AudioGenerator.generateAll(
      provider,
      units,
      voiceName,
      outputDirectory: documentTree ? null : outputDirectory,
      fileWriter: documentTree
          ? (String filename, Uint8List bytes) =>
                OutputDirectoryService.writeFile(
                  outputDirectory,
                  filename,
                  bytes,
                )
          : null,
      startIndex: 0,
      existingPaths: generatedPaths,
      rate: 1 + ratePercent / 100,
      volume: volumePercent,
      pitch: pitchHz,
      autoSplit: autoSplit,
      retryLongSentences: autoRetry,
      onChunkProgress: onChunkProgress,
      onProgress: onProgress,
      onFileGenerated: onFileGenerated,
    );
  }

  Future<void> stopPreview() async {
    await player.stop();
    await player.seekToStart();
  }

  Future<void> dispose() async {
    await player.stop();
    await player.dispose();
  }
}
