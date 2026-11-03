import 'dart:typed_data';

import '../models/chapter.dart';
import '../providers/tts_provider.dart';
import '../services/audio_generator.dart';
import '../services/audio_generation_cancellation.dart';
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
  AudioGenerationCancellation? _activeCancellation;
  bool _cancelRequested = false;
  bool _preparingGeneration = false;

  bool get isGenerating => _activeCancellation != null;
  bool get canCancel => _preparingGeneration || isGenerating;

  void prepareGeneration() {
    _preparingGeneration = true;
    _cancelRequested = false;
  }

  void clearPendingGeneration() {
    _preparingGeneration = false;
    if (_activeCancellation == null) _cancelRequested = false;
  }

  void cancel() {
    if (!canCancel) return;
    _cancelRequested = true;
    _activeCancellation?.cancel();
  }

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
    try {
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
      final file = await AudioGenerator.writeTemporary(
        bytes,
        'tts-preview.mp3',
      );
      await player.setFilePath(file);
      await player.play();
    } finally {
      closeTtsProvider(provider);
    }
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
  }) async {
    final cancellation = AudioGenerationCancellation();
    _activeCancellation = cancellation;
    _preparingGeneration = false;
    if (_cancelRequested) cancellation.cancel();
    final documentTree =
        outputDirectory != null &&
        OutputDirectoryService.isAndroidDocumentTree(outputDirectory);
    try {
      return await AudioGenerator.generateAll(
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
        cancellation: cancellation,
      );
    } finally {
      _activeCancellation = null;
      _preparingGeneration = false;
      _cancelRequested = false;
      closeTtsProvider(provider);
    }
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
