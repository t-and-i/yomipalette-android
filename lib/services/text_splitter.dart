import 'dart:math' as math;

import '../models/chapter.dart';

final RegExp _boundary = RegExp(r'[。．.!?！？\n]');

List<Chapter> splitChaptersByChars(List<Chapter> chapters, int maxChars) {
  if (maxChars <= 0) {
    throw ArgumentError.value(maxChars, 'maxChars', 'must be positive');
  }
  final fullText = chapters
      .where((chapter) => chapter.text.isNotEmpty)
      .map((chapter) => chapter.text)
      .join('\n');
  if (fullText.trim().isEmpty) return const [];

  final parts = <Chapter>[];
  var offset = 0;
  while (offset < fullText.length) {
    final remaining = fullText.length - offset;
    var length = remaining <= maxChars ? remaining : maxChars;
    if (remaining > maxChars) {
      final window = fullText.substring(offset, offset + maxChars);
      final matches = _boundary.allMatches(window);
      if (matches.isNotEmpty) length = matches.last.end;
    }
    final text = fullText.substring(offset, offset + length);
    if (text.trim().isNotEmpty) {
      final index = parts.length + 1;
      parts.add(Chapter(
        index: index,
        title: 'Part ${index.toString().padLeft(3, '0')}',
        text: text,
      ));
    }
    offset += length;
  }
  return parts;
}

String previewText(String text, {int maxChars = 150}) {
  final cleaned = text.trim();
  if (cleaned.isEmpty || maxChars <= 0) return '';
  final window = cleaned.substring(0, math.min(cleaned.length, maxChars));
  final matches = _boundary.allMatches(window);
  if (matches.isNotEmpty && matches.last.end >= maxChars * .6) {
    return window.substring(0, matches.last.end).trim();
  }
  return window;
}
