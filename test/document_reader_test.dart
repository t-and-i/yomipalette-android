import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_text_mp3_mobile/services/document_reader.dart';

void main() {
  test('auto detects UTF-8 with BOM', () async {
    final bytes = Uint8List.fromList([
      0xef,
      0xbb,
      0xbf,
      ...utf8.encode('日本語の文章です。'),
    ]);

    expect(await DocumentReader.decodeText(bytes), '日本語の文章です。');
  });

  test('auto detects UTF-16 LE and BE with BOM', () async {
    final le = _utf16Bytes('日本語。', littleEndian: true, bom: true);
    final be = _utf16Bytes('中文。', littleEndian: false, bom: true);

    expect(await DocumentReader.decodeText(le), '日本語。');
    expect(await DocumentReader.decodeText(be), '中文。');
  });

  test('auto detects UTF-16 without BOM from null-byte pattern', () async {
    final bytes = _utf16Bytes('English text.', littleEndian: true, bom: false);

    expect(await DocumentReader.decodeText(bytes), 'English text.');
  });

  test('manual UTF-16 selection decodes without BOM', () async {
    final bytes = _utf16Bytes('文字コード', littleEndian: false, bom: false);

    expect(
      await DocumentReader.decodeText(bytes, 'utf-16be'),
      '文字コード',
    );
  });

  test('auto detects UTF-32 LE and BE with BOM', () async {
    final le = _utf32Bytes('日本語。', littleEndian: true);
    final be = _utf32Bytes('中文。', littleEndian: false);

    expect(await DocumentReader.decodeText(le), '日本語。');
    expect(await DocumentReader.decodeText(be), '中文。');
  });
}

Uint8List _utf16Bytes(
  String text, {
  required bool littleEndian,
  required bool bom,
}) {
  final bytes = <int>[];
  if (bom) bytes.addAll(littleEndian ? [0xff, 0xfe] : [0xfe, 0xff]);
  for (final unit in text.codeUnits) {
    bytes.addAll(
        littleEndian ? [unit & 0xff, unit >> 8] : [unit >> 8, unit & 0xff]);
  }
  return Uint8List.fromList(bytes);
}

Uint8List _utf32Bytes(String text, {required bool littleEndian}) {
  final bytes = <int>[
    ...(littleEndian ? [0xff, 0xfe, 0x00, 0x00] : [0x00, 0x00, 0xfe, 0xff]),
  ];
  for (final rune in text.runes) {
    bytes.addAll(littleEndian
        ? [rune & 0xff, (rune >> 8) & 0xff, (rune >> 16) & 0xff, rune >> 24]
        : [rune >> 24, (rune >> 16) & 0xff, (rune >> 8) & 0xff, rune & 0xff]);
  }
  return Uint8List.fromList(bytes);
}
