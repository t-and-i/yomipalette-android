import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_text_mp3_mobile/models/chapter.dart';
import 'package:tts_text_mp3_mobile/providers/tts_provider.dart';
import 'package:tts_text_mp3_mobile/services/audio_generator.dart';

void main() {
  test('generation can resume from the first unfinished unit', () async {
    final directory = await Directory.systemTemp.createTemp('tts-resume-');
    addTearDown(() => directory.delete(recursive: true));
    final units = [
      const Chapter(index: 1, title: 'Part 001', text: 'one'),
      const Chapter(index: 2, title: 'Part 002', text: 'two'),
      const Chapter(index: 3, title: 'Part 003', text: 'three'),
    ];
    final completed = <String>[];
    var nextIndex = 0;

    await expectLater(
      AudioGenerator.generateAll(
        _FailingProvider(failOnCall: 2),
        units,
        'voice',
        outputDirectory: directory.path,
        onFileGenerated: (path, current, total) {
          completed.add(path);
          nextIndex = current;
        },
      ),
      throwsA(isA<TtsProviderException>()),
    );

    expect(nextIndex, 1);
    expect(completed, hasLength(1));

    final paths = await AudioGenerator.generateAll(
      _FailingProvider(),
      units,
      'new-voice',
      outputDirectory: directory.path,
      startIndex: nextIndex,
      existingPaths: completed,
    );

    expect(paths, hasLength(3));
    expect(paths.every((path) => File(path).existsSync()), isTrue);
  });

  test('writable directory check does not leave its probe file', () async {
    final directory = await Directory.systemTemp.createTemp('tts-output-');
    addTearDown(() => directory.delete(recursive: true));

    await AudioGenerator.verifyWritableDirectory(directory.path);

    expect(directory.listSync(), isEmpty);
  });

  test('generated app copies can be deleted after sharing', () async {
    final directory = await Directory.systemTemp.createTemp('tts-delete-');
    addTearDown(() => directory.delete(recursive: true));
    final first = File('${directory.path}${Platform.pathSeparator}first.mp3');
    final second = File('${directory.path}${Platform.pathSeparator}second.mp3');
    await first.writeAsBytes([1]);
    await second.writeAsBytes([2]);

    await AudioGenerator.deleteFiles([first.path, second.path]);

    expect(first.existsSync(), isFalse);
    expect(second.existsSync(), isFalse);
  });
}

class _FailingProvider implements TtsProvider {
  _FailingProvider({this.failOnCall});
  final int? failOnCall;
  var calls = 0;

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
      throw const TtsProviderException('usage limit');
    }
    return Uint8List.fromList([calls]);
  }
}
