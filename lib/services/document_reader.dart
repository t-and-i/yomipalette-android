import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:epubx/epubx.dart';

import '../models/chapter.dart';

class DocumentReader {
  static Future<List<Chapter>> read(String name, Uint8List bytes) async {
    final lower = name.toLowerCase();
    if (lower.endsWith('.txt')) return _readText(name, bytes);
    if (lower.endsWith('.epub')) return _readEpub(bytes);
    throw const FormatException('Only TXT and EPUB files are supported.');
  }

  static Future<List<Chapter>> _readText(String name, Uint8List bytes) async {
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      // The desktop app commonly receives Japanese Windows TXT files. The
      // platform converter uses the native charset implementation on mobile.
      try {
        text = await CharsetConverter.decode('Shift_JIS', bytes);
      } catch (_) {
        text = latin1.decode(bytes);
      }
    }
    final title = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return [Chapter(index: 1, title: title, text: _clean(text))];
  }

  static Future<List<Chapter>> _readEpub(Uint8List bytes) async {
    final book = await EpubReader.readBook(bytes);
    final result = <Chapter>[];
    void visit(List<EpubChapter>? chapters) {
      for (final chapter in chapters ?? const <EpubChapter>[]) {
        final text = _clean(_stripHtml(chapter.HtmlContent ?? ''));
        if (text.isNotEmpty) {
          final index = result.length + 1;
          result.add(Chapter(
            index: index,
            title: (chapter.Title?.trim().isNotEmpty ?? false)
                ? chapter.Title!.trim()
                : 'Chapter $index',
            text: text,
          ));
        }
        visit(chapter.SubChapters);
      }
    }

    visit(book.Chapters);
    if (result.isEmpty) throw const FormatException('No readable text found.');
    return result;
  }

  static String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', dotAll: true), '')
      .replaceAll(
          RegExp(r'<br\s*/?>|</p>|</div>|</h[1-6]>', caseSensitive: false),
          '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"');

  static String _clean(String text) => text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' ?\n ?'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
