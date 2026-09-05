import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_text_mp3_mobile/services/document_reader.dart';

void main() {
  final cases =
      jsonDecode(File('../tests/fixtures/epub_cases.json').readAsStringSync())
          as List;
  for (final fixture in cases) {
    test('EPUB ${fixture['name']}', () async {
      final archive = Archive();
      for (final entry in (fixture['resources'] as Map).entries) {
        final encoding = (fixture['encodings'] as Map?)?[entry.key] ?? 'utf-8';
        final text = entry.value as String;
        final bytes = encoding == 'utf-8'
            ? utf8.encode(text)
            : <int>[
                if (encoding == 'utf-16') ...[0xff, 0xfe],
                for (final unit in text.codeUnits)
                  ...encoding == 'utf-16-be'
                      ? [unit >> 8, unit & 255]
                      : [unit & 255, unit >> 8],
              ];
        archive.addFile(ArchiveFile(entry.key as String, bytes.length, bytes));
      }
      final chapters = await DocumentReader.read(
          'fixture.epub', Uint8List.fromList(ZipEncoder().encode(archive)!));
      expect(chapters.map((c) => {'title': c.title, 'text': c.text}).toList(),
          fixture['expected']);
      expect(chapters.map((c) => c.index).toList(),
          List.generate(chapters.length, (i) => i + 1));
    });
  }
}
