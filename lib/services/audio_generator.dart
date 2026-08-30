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
    String voice,
  ) async {
    final builder = BytesBuilder(copy: false);
    var offset = 0;
    while (offset < text.length) {
      final end = math.min(offset + providerChunkSize, text.length);
      builder
          .add(await provider.synthesize(text.substring(offset, end), voice));
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
    void Function(int current, int total)? onProgress,
  }) async {
    final root = await getApplicationDocumentsDirectory();
    final output = Directory(path.join(root.path, 'TTS Text to MP3'));
    await output.create(recursive: true);
    final paths = <String>[];
    for (var index = 0; index < units.length; index++) {
      final unit = units[index];
      final bytes = await synthesizeLong(provider, unit.text, voice);
      final safeTitle =
          unit.title.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_');
      final filename =
          '${unit.index.toString().padLeft(3, '0')}_${safeTitle.isEmpty ? 'untitled' : safeTitle}.mp3';
      final file = File(path.join(output.path, filename));
      await file.writeAsBytes(bytes, flush: true);
      paths.add(file.path);
      onProgress?.call(index + 1, units.length);
    }
    return paths;
  }
}
