import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'audio_generator.dart';

class OutputDirectorySelection {
  const OutputDirectorySelection({required this.id, required this.label});
  final String id;
  final String label;
}

class OutputDirectoryService {
  static const _channel = MethodChannel('tts_text_mp3/output_directory');

  static bool isAndroidDocumentTree(String id) => id.startsWith('content://');

  static Future<OutputDirectorySelection?> select() async {
    if (Platform.isAndroid) {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'selectDirectory',
      );
      if (result == null) return null;
      return OutputDirectorySelection(
        id: result['uri'] as String,
        label: result['label'] as String,
      );
    }
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return null;
    await AudioGenerator.verifyWritableDirectory(path);
    return OutputDirectorySelection(id: path, label: path);
  }

  static Future<void> verify(String id) async {
    if (Platform.isAndroid && isAndroidDocumentTree(id)) {
      await _channel.invokeMethod<void>('verifyDirectory', {'uri': id});
      return;
    }
    await AudioGenerator.verifyWritableDirectory(id);
  }

  static Future<String> writeFile(
    String directoryId,
    String filename,
    Uint8List bytes,
  ) async {
    if (Platform.isAndroid && isAndroidDocumentTree(directoryId)) {
      final uri = await _channel.invokeMethod<String>('writeFile', {
        'uri': directoryId,
        'name': filename,
        'bytes': bytes,
      });
      if (uri == null) throw const FileSystemException('File was not saved.');
      return uri;
    }
    final file = File('$directoryId${Platform.pathSeparator}$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
