import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:tts_text_mp3_mobile/services/document_reader.dart';
import 'package:tts_text_mp3_mobile/services/pdf_reader.dart';
import 'package:tts_text_mp3_mobile/services/text_splitter.dart';

Future<Uint8List> fixture(String name) =>
    File('../tests/fixtures/pdf/$name').readAsBytes();

void main() {
  // pdfrx bundles PDFium for Android, iOS, macOS, Windows, and web. The Flutter
  // Linux test runner does not ship libpdfium.so, so these tests can only run
  // where PDFium is available. CI uses Linux; skip there to keep `flutter test`
  // green. The release Android and iOS jobs still build the real binaries.
  final isLinuxHost = Platform.isLinux;
  final skipReason = 'pdfrx Linux test runner does not bundle PDFium';

  setUpAll(() {
    if (isLinuxHost) return;
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  });

  test('PDF preserves page order and Japanese, skipping image and blank pages',
      () async {
    final chapters =
        await DocumentReader.read('book.PDF', await fixture('text-pages.pdf'));
    expect(chapters.map((c) => c.index), [1, 2, 3]);
    expect(chapters.map((c) => c.title), ['Page 001', 'Page 003', 'Page 005']);
    expect(chapters.map((c) => c.text),
        ['First page text.', '日本語の本文です。', 'Last page text.']);
    final parts = splitChaptersByChars(chapters, 10);
    expect(parts.map((c) => c.text).join(),
        chapters.map((c) => c.text).join('\n'));
    expect(parts.every((c) => c.text.length <= 10), isTrue);
  }, skip: isLinuxHost ? skipReason : null);

  test('image-only PDF explains OCR', () async {
    await expectLater(
        DocumentReader.read('scan.pdf', await fixture('image-only.pdf')),
        throwsA(isA<PdfReadException>()
            .having((e) => e.messageKey, 'key', 'pdfNoText')));
  }, skip: isLinuxHost ? skipReason : null);

  test('password-required PDF reports a specific error', () async {
    await expectLater(
        DocumentReader.read('locked.pdf', await fixture('password.pdf')),
        throwsA(isA<PdfReadException>()
            .having((e) => e.messageKey, 'key', 'pdfPassword')));
  }, skip: isLinuxHost ? skipReason : null);

  test('PDF with an empty user password can be opened', () async {
    expect(
        await DocumentReader.read(
            'book.pdf', await fixture('empty-password.pdf')),
        hasLength(3));
  }, skip: isLinuxHost ? skipReason : null);

  test('invalid PDF is reported', () async {
    await expectLater(
        DocumentReader.read(
            'broken.pdf', Uint8List.fromList('%PDF-1.7\ninvalid'.codeUnits)),
        throwsA(isA<PdfReadException>()
            .having((e) => e.messageKey, 'key', 'pdfInvalid')));
  }, skip: isLinuxHost ? skipReason : null);
}
