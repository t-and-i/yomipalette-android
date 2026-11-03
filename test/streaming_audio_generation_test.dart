import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_text_mp3_mobile/models/chapter.dart';
import 'package:tts_text_mp3_mobile/providers/tts_provider.dart';
import 'package:tts_text_mp3_mobile/services/audio_generation_cancellation.dart';
import 'package:tts_text_mp3_mobile/services/audio_generator.dart';

class _Provider implements TtsProvider {
  _Provider({this.failOnCall});
  final int? failOnCall;
  int calls = 0;

  @override
  Future<List<VoiceInfo>> listVoices() async => const [];

  @override
  Future<Uint8List> synthesize(
    String text,
    String voice, {
    double rate = 1,
    double volume = 0,
    double pitch = 0,
  }) async {
    calls++;
    if (calls == failOnCall) {
      throw const TtsProviderException('simulated synthesis failure');
    }
    return Uint8List.fromList([calls]);
  }
}

void main() {
  test('multiple chunks stream into one completed file', () async {
    final directory = await Directory.systemTemp.createTemp('yomi-phase3-');
    addTearDown(() => directory.delete(recursive: true));
    final provider = _Provider();
    final progress = <(int, int, bool)>[];
    final outputs = await AudioGenerator.generateAll(
      provider,
      [Chapter(index: 1, title: 'chapter', text: 'x' * 3700)],
      'voice',
      outputDirectory: directory.path,
      onChunkProgress: (unit, total, chunk, count, retrying) =>
          progress.add((chunk, count, retrying)),
    );

    expect(provider.calls, 3);
    expect(outputs, hasLength(1));
    expect(await File(outputs.single).readAsBytes(), [1, 2, 3]);
    expect(progress.last.$1, 3);
    expect(progress.last.$2, 3);
    expect(directory.listSync().whereType<Directory>(), isEmpty);
  });

  test('failed long generation keeps old file and clears staging', () async {
    final directory = await Directory.systemTemp.createTemp('yomi-fail-');
    addTearDown(() => directory.delete(recursive: true));
    final existing = File(
      '${directory.path}${Platform.pathSeparator}001_chapter.mp3',
    );
    await existing.writeAsBytes([55, 66, 77], flush: true);

    await expectLater(
      AudioGenerator.generateAll(
        _Provider(failOnCall: 2),
        [Chapter(index: 1, title: 'chapter', text: 'x' * 3700)],
        'voice',
        outputDirectory: directory.path,
      ),
      throwsA(isA<TtsProviderException>()),
    );

    expect(await existing.readAsBytes(), [55, 66, 77]);
    expect(directory.listSync(), hasLength(1));
  });

  test('cancel between chunks preserves original output file', () async {
    final directory = await Directory.systemTemp.createTemp('yomi-cancel-');
    addTearDown(() => directory.delete(recursive: true));
    final original = File(
      '${directory.path}${Platform.pathSeparator}001_chapter.mp3',
    );
    await original.writeAsBytes([19, 20]);
    final token = AudioGenerationCancellation();

    await expectLater(
      AudioGenerator.generateAll(
        _Provider(),
        [Chapter(index: 1, title: 'chapter', text: 'x' * 3800)],
        'voice',
        outputDirectory: directory.path,
        cancellation: token,
        onChunkProgress: (_, __, completed, ___, ____) {
          if (completed == 1) token.cancel();
        },
      ),
      throwsA(isA<AudioGenerationCancelled>()),
    );

    expect(await original.readAsBytes(), [19, 20]);
    expect(directory.listSync(), hasLength(1));
  });

  test('Android-like writer sees only complete accumulated MP3', () async {
    final directory = await Directory.systemTemp.createTemp('yomi-saf-');
    addTearDown(() => directory.delete(recursive: true));
    final written = <String, Uint8List>{};
    var calls = 0;

    final result = await AudioGenerator.generateAll(
      _Provider(),
      [Chapter(index: 7, title: 'voice', text: 'x' * 3700)],
      'voice',
      stagingDirectory: directory,
      fileWriter: (filename, bytes) async {
        calls++;
        written[filename] = bytes;
        return 'content://qa/$filename';
      },
    );
    expect(calls, 1);
    expect(written['007_voice.mp3'], [1, 2, 3]);
    expect(result, ['content://qa/007_voice.mp3']);
    expect(directory.listSync(), isEmpty);
  });

  test('failed writer is not retried and staging is cleaned', () async {
    final directory = await Directory.systemTemp.createTemp('yomi-writer-');
    addTearDown(() => directory.delete(recursive: true));
    var writes = 0;

    await expectLater(
      AudioGenerator.generateAll(
        _Provider(),
        [const Chapter(index: 1, title: 'unit', text: 'audio')],
        'voice',
        stagingDirectory: directory,
        fileWriter: (_, bytes) async {
          writes++;
          throw const FileSystemException('Cannot write the file');
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(writes, 1);
    expect(directory.listSync(), isEmpty);
  });

  test(
    'cancel after one completed unit retains only published outputs',
    () async {
      final directory = await Directory.systemTemp.createTemp('yomi-partial-');
      addTearDown(() => directory.delete(recursive: true));
      final token = AudioGenerationCancellation();
      final outputs = <String>[];

      await expectLater(
        AudioGenerator.generateAll(
          _Provider(),
          const [
            Chapter(index: 1, title: 'one', text: 'first'),
            Chapter(index: 2, title: 'two', text: 'second'),
          ],
          'voice',
          outputDirectory: directory.path,
          cancellation: token,
          onFileGenerated: (path, current, total) {
            outputs.add(path);
            if (current == 1) token.cancel();
          },
        ),
        throwsA(isA<AudioGenerationCancelled>()),
      );
      expect(outputs, hasLength(1));
      expect(await File(outputs.single).readAsBytes(), [1]);
      expect(directory.listSync(), hasLength(1));
    },
  );
}
