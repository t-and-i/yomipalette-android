import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/chapter.dart';
import '../providers/tts_provider.dart';

class AudioGenerator {
  static const providerChunkSize = 1800;

  static Future<Uint8List> synthesizeLong(
    TtsProvider provider,
    String text,
    String voice, {
    double rate = 1,
    double volume = 0,
    double pitch = 0,
  }) async {
    final builder = BytesBuilder(copy: false);
    var offset = 0;
    while (offset < text.length) {
      final end = math.min(offset + providerChunkSize, text.length);
      builder.add(await provider.synthesize(
        text.substring(offset, end),
        voice,
        rate: rate,
        volume: volume,
        pitch: pitch,
      ));
      offset = end;
    }
    return builder.takeBytes();
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
    void Function(int current, int total)? onProgress,
    void Function(String path, int current, int total)? onFileGenerated,
  }) async {
    if (startIndex < 0 || startIndex > units.length) {
      throw RangeError.range(startIndex, 0, units.length, 'startIndex');
    }
    final output = outputDirectory == null && fileWriter == null
        ? Directory(path.join(
            (await getApplicationDocumentsDirectory()).path,
            'TTS Text to MP3',
          ))
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
      );
      final safeTitle =
          unit.title.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_');
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
          'The selected folder does not exist.', directoryPath);
    }
    final probe = File(path.join(
      directory.path,
      '.tts-text-mp3-write-test-${DateTime.now().microsecondsSinceEpoch}',
    ));
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
