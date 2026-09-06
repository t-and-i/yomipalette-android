import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../models/chapter.dart';

class PdfReadException implements Exception {
  const PdfReadException(this.messageKey);
  final String messageKey;
}

/// Reads embedded text in physical page order, without OCR or outline parsing.
Future<List<Chapter>> readPdfSections(Uint8List bytes) async {
  await pdfrxFlutterInitialize();
  PdfDocument? document;
  try {
    document = await PdfDocument.openData(bytes);
    final chapters = <Chapter>[];
    for (final page in document.pages) {
      final raw = await page.loadText();
      if (raw == null) throw const PdfReadException('pdfInvalid');
      final text = raw.fullText
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .replaceAll(RegExp(r' ?\n ?'), '\n')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
      if (text.isEmpty) continue;
      chapters.add(Chapter(
        index: chapters.length + 1,
        title: 'Page ${page.pageNumber.toString().padLeft(3, '0')}',
        text: text,
      ));
    }
    if (chapters.isEmpty) throw const PdfReadException('pdfNoText');
    return chapters;
  } on PdfPasswordException {
    throw const PdfReadException('pdfPassword');
  } on PdfException {
    throw const PdfReadException('pdfInvalid');
  } finally {
    await document?.dispose();
  }
}
