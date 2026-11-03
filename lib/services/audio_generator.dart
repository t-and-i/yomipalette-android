import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/chapter.dart';
import '../providers/google_provider.dart';
import '../providers/tts_provider.dart';
import 'audio_generation_cancellation.dart';
import 'mp3_joiner.dart';
import 'tts_chunking.dart';

class AudioGenerator {
  static const providerChunkSize = 1800;

  /// Small preview compatibility API. For complete books, use generateAll()
  /// which writes audio incrementally to a staging file instead.
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
    final audioClips = <Uint8List>[];
    await _forEachClip(
      provider,
      text,
      voice,
      rate: rate,
      volume: volume,
      pitch: pitch,
      autoSplit: autoSplit,
      retryLongSentences: retryLongSentences,
      onChunkProgress: onChunkProgress,
      onClip: (clip) async => audioClips.add(clip),
    );

    final google = provider is GoogleProvider;
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

  /// Centralized split/retry policy shared by preview and streaming output.
  ///
  /// Errors from the audio sink are propagated; only Google's explicit
  /// sentence-too-long response can cause recursive splitting.
  static Future<void> _forEachClip(
    TtsProvider provider,
    String text,
    String voice, {
    required Future<void> Function(Uint8List bytes) onClip,
    double rate = 1,
    double volume = 0,
    double pitch = 0,
    bool autoSplit = true,
    bool retryLongSentences = true,
    void Function(int completed, int total, bool retrying)? onChunkProgress,
    AudioGenerationCancellation? cancellation,
  }) async {
    if (text.isEmpty) return;
    final google = provider is GoogleProvider;
    final policy = TtsChunkPolicy.forVoice(google ? 'google' : 'other', voice);
    final chunks = autoSplit ? splitTtsText(text, policy) : [text];
    var total = chunks.length;
    var completed = 0;
    var retries = 0;
    const maxRetryRequests = 32;

    Future<void> synthesizeChunk(
      String chunk,
      TtsChunkPolicy limit,
      int depth,
    ) async {
      cancellation?.throwIfCancelled();
      Uint8List bytes;
      try {
        bytes = await provider.synthesize(
          chunk,
          voice,
          rate: rate,
          volume: volume,
          pitch: pitch,
        );
      } catch (error) {
        cancellation?.throwIfCancelled();
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
        return;
      }
      cancellation?.throwIfCancelled();
      await onClip(bytes);
      completed++;
      onChunkProgress?.call(completed, total, false);
    }

    for (final chunk in chunks) {
      await synthesizeChunk(chunk, policy, 0);
    }
  }

  /// Each chunk is persisted before fetching the next one. Google MP3 clips
  /// need one continuous encoder stream, whereas other provider MP3 bytes
  /// preserve their existing concatenation behavior.
  static Future<void> _synthesizeToFile(
    TtsProvider provider,
    String text,
    String voice,
    File staged, {
    required double rate,
    required double volume,
    required double pitch,
    required bool autoSplit,
    required bool retryLongSentences,
    required void Function(int completed, int total, bool retrying)?
    onChunkProgress,
    AudioGenerationCancellation? cancellation,
  }) async {
    final sink = staged.openWrite();
    final google = provider is GoogleProvider;
    Uint8List? firstGoogleClip;
    Mp3JoinSession? session;
    var complete = false;
    try {
      await _forEachClip(
        provider,
        text,
        voice,
        rate: rate,
        volume: volume,
        pitch: pitch,
        autoSplit: autoSplit,
        retryLongSentences: retryLongSentences,
        cancellation: cancellation,
        onChunkProgress: onChunkProgress,
        onClip: (clip) async {
          if (!google) {
            sink.add(clip);
            await sink.flush();
            return;
          }
          final first = firstGoogleClip;
          if (first == null && session == null) {
            firstGoogleClip = clip;
            return;
          }
          session ??= Mp3JoinSession();
          if (first != null) {
            sink.add(await session!.add(first));
            firstGoogleClip = null;
          }
          sink.add(await session!.add(clip));
          await sink.flush();
        },
      );
      cancellation?.throwIfCancelled();
      if (session != null) {
        sink.add(await session!.finish());
      } else if (firstGoogleClip != null) {
        // Avoid re-encoding the only Google MP3 clip.
        sink.add(firstGoogleClip!);
      }
      await sink.flush();
      await sink.close();
      complete = true;
    } finally {
      await session?.close();
      if (!complete) {
        try {
          await sink.close();
        } catch (_) {
          // The original generation error is more useful than cleanup errors.
        }
      }
    }
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
    Directory? stagingDirectory,
    AudioGenerationCancellation? cancellation,
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
      cancellation?.throwIfCancelled();
      final unit = units[index];
      final safeTitle = unit.title.replaceAll(
        RegExp(r'[\\/:*?"<>|\r\n\t]'),
        '_',
      );
      final filename =
          "${unit.index.toString().padLeft(3, '0')}_${safeTitle.isEmpty ? 'untitled' : safeTitle}.mp3";

      // Local files stage on the same filesystem so rename is inexpensive.
      // SAF needs an app-private temp file, and only the completed MP3 is
      // sent over the method channel. We never retain all source clips.
      final stageBase =
          output ?? stagingDirectory ?? await getTemporaryDirectory();
      final work = await stageBase.createTemp('.yomipalette-stage-');
      try {
        final staged = File(path.join(work.path, filename));
        await _synthesizeToFile(
          provider,
          unit.text,
          voice,
          staged,
          rate: rate,
          volume: volume,
          pitch: pitch,
          autoSplit: autoSplit,
          retryLongSentences: retryLongSentences,
          cancellation: cancellation,
          onChunkProgress: (current, total, retrying) => onChunkProgress?.call(
            index + 1,
            units.length,
            current,
            total,
            retrying,
          ),
        );
        cancellation?.throwIfCancelled();
        final savedPath = fileWriter == null
            ? await _publishLocalFile(
                staged,
                File(path.join(output!.path, filename)),
              )
            : await fileWriter(filename, await staged.readAsBytes());
        paths.add(savedPath);
        onProgress?.call(index + 1, units.length);
        onFileGenerated?.call(savedPath, index + 1, units.length);
      } finally {
        if (await work.exists()) {
          await work.delete(recursive: true);
        }
      }
    }
    return paths;
  }

  /// Keep the existing file recoverable even if final publication fails.
  static Future<String> _publishLocalFile(File staged, File target) async {
    if (!await target.exists()) {
      return (await staged.rename(target.path)).path;
    }

    final backup = File(
      '${target.path}.yomipalette-backup-${DateTime.now().microsecondsSinceEpoch}',
    );
    await target.rename(backup.path);
    try {
      final result = await staged.rename(target.path);
      try {
        await backup.delete();
      } catch (_) {
        // A failed backup cleanup is preferable to deleting user audio.
      }
      return result.path;
    } catch (_) {
      // Roll back, never silently remove the previous audio.
      await backup.rename(target.path);
      rethrow;
    }
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
