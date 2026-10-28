import 'dart:io';
// Chunking and retry logic live in tts_chunking.dart.
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/chapter.dart';
import '../providers/google_provider.dart';
import '../providers/tts_provider.dart';
import 'mp3_joiner.dart';
import 'tts_chunking.dart';

class AudioGenerator {
  static const providerChunkSize = 1800;

  static Future<Uint8List> synthesizeLong(
    TtsProvider provider,
    String text,
    String voice, {
    double rate = 1,
    double volume = 0,
    double pitch = 0,
    bool autoSplit = true,
    bool retryLongSentences = true,
    void Function(int completed, int total, bool retrying)? onChunkProgress,
    Future<Uint8List> Function(List<Uint8List>)? mp3Joiner,
  }) async {
    if (text.isEmpty) return Uint8List(0);
    final google = provider is GoogleProvider;
    final policy = TtsChunkPolicy.forVoice(google ? 'google' : 'other', voice);
    final chunks = autoSplit ? splitTtsText(text, policy) : [text];
    final audioClips = <Uint8List>[];
    var total = chunks.length;
    var completed = 0;
    var retries = 0;
    const maxRetryRequests = 32;

    Future<void> synthesizeChunk(
      String chunk,
      TtsChunkPolicy limit,
      int depth,
    ) async {
      try {
        final bytes = await provider.synthesize(
          chunk,
          voice,
          rate: rate,
          volume: volume,
          pitch: pitch,
        );
        audioClips.add(bytes);
        completed++;
        onChunkProgress?.call(completed, total, false);
      } catch (error) {
        if (!google ||
            !retryLongSentences ||
            !isSentenceTooLongError(error) ||
            depth >= 5 ||
            retries >= maxRetryRequests ||
            chunk.runes.length <= 12) {
          throw TtsProviderException(
            'Audio segment ${completed + 1}/$total failed: $error',
          );
        }
        final smaller = limit.smaller();
        final pieces = splitTtsText(chunk, smaller);
        if (pieces.length < 2) rethrow;
        retries++;
        total += pieces.length - 1;
        onChunkProgress?.call(completed, total, true);
        for (final part in pieces) {
          await synthesizeChunk(part, smaller, depth + 1);
        }
      }
    }

    for (final chunk in chunks) {
      await synthesizeChunk(chunk, policy, 0);
    }
    // For Google, decode to PCM and re-encode one continuous MP3 stream.
    // Other providers retain their legacy byte-stream behavior.
    if (google && audioClips.length > 1) {
      return (mp3Joiner ?? Mp3Joiner.join)(audioClips);
    }
    if (audioClips.length == 1) return audioClips.single;
    final result = BytesBuilder(copy: false);
    for (final clip in audioClips) {
      result.add(clip);
    }
    return result.takeBytes();
  }

  static Future<String> writeTemporary(Uint8List bytes, String name) async {
    final directory = await getTemporaryDirectory();
    final file = File(path.join(directory.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<List<String>> generateAll(
    TtsProvider provider,
    List<Chapter> units,
    String voice, {
    String? outputDirectory,
    Future<String> Function(String filename, Uint8List bytes)? fileWriter,
    int startIndex = 0,
    List<String> existingPaths = const [],
    double rate = 1,
    double volume = 0,
    double pitch = 0,
    bool autoSplit = true,
    bool retryLongSentences = true,
    void Function(
      int unit,
      int unitTotal,
      int chunk,
      int chunkTotal,
      bool retrying,
    )?
    onChunkProgress,
    void Function(int current, int total)? onProgress,
    void Function(String path, int current, int total)? onFileGenerated,
  }) async {
    if (startIndex < 0 || startIndex > units.length) {
      throw RangeError.range(startIndex, 0, units.length, 'startIndex');
    }
    final output = outputDirectory == null && fileWriter == null
        ? Directory(
            path.join(
              (await getApplicationDocumentsDirectory()).path,
              'YomiPalette',
            ),
          )
        : outputDirectory == null
        ? null
        : Directory(outputDirectory);
    await output?.create(recursive: true);
    final paths = List<String>.from(existingPaths);
    for (var index = startIndex; index < units.length; index++) {
      final unit = units[index];
      final bytes = await synthesizeLong(
        provider,
        unit.text,
        voice,
        rate: rate,
        volume: volume,
        pitch: pitch,
        autoSplit: autoSplit,
        retryLongSentences: retryLongSentences,
        onChunkProgress: (current, total, retrying) => onChunkProgress?.call(
          index + 1,
          units.length,
          current,
          total,
          retrying,
        ),
      );
      final safeTitle = unit.title.replaceAll(
        RegExp(r'[\\/:*?"<>|\r\n\t]'),
        '_',
      );
      final filename =
          '${unit.index.toString().padLeft(3, '0')}_${safeTitle.isEmpty ? 'untitled' : safeTitle}.mp3';
      final savedPath = fileWriter == null
          ? await _writeFile(output!, filename, bytes)
          : await fileWriter(filename, bytes);
      paths.add(savedPath);
      onProgress?.call(index + 1, units.length);
      onFileGenerated?.call(savedPath, index + 1, units.length);
    }
    return paths;
  }

  static Future<String> _writeFile(
    Directory output,
    String filename,
    Uint8List bytes,
  ) async {
    final file = File(path.join(output.path, filename));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<void> verifyWritableDirectory(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      throw FileSystemException(
        'The selected folder does not exist.',
        directoryPath,
      );
    }
    final probe = File(
      path.join(
        directory.path,
        '.tts-text-mp3-write-test-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      await probe.writeAsString('write test', flush: true);
    } on FileSystemException catch (error) {
      throw FileSystemException(
        'The selected folder is not writable.',
        directoryPath,
        error.osError,
      );
    } finally {
      if (await probe.exists()) await probe.delete();
    }
  }

  static Future<void> deleteFiles(Iterable<String> paths) async {
    for (final filePath in paths) {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    }
  }
}
