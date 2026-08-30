import 'package:flutter_test/flutter_test.dart';
import 'package:tts_text_mp3_mobile/models/chapter.dart';
import 'package:tts_text_mp3_mobile/services/text_splitter.dart';

void main() {
  test('joins chapters and preserves all text', () {
    const chapters = [
      Chapter(index: 1, title: 'A', text: 'abc。def'),
      Chapter(index: 2, title: 'B', text: 'ghi。jkl'),
    ];
    final parts = splitChaptersByChars(chapters, 6);
    expect(parts.map((part) => part.text).join(), 'abc。def\nghi。jkl');
    expect(parts.every((part) => part.text.length <= 6), isTrue);
    expect(parts.first.title, 'Part 001');
  });

  test('uses the last sentence boundary within the limit', () {
    const chapters = [Chapter(index: 1, title: 'A', text: 'abc。def。ghi')];
    final parts = splitChaptersByChars(chapters, 8);
    expect(parts.first.text, 'abc。def。');
  });

  test('force-splits text without a boundary', () {
    const chapters = [Chapter(index: 1, title: 'A', text: 'abcdefghij')];
    final parts = splitChaptersByChars(chapters, 4);
    expect(parts.map((part) => part.text), ['abcd', 'efgh', 'ij']);
  });

  test('rejects a non-positive limit', () {
    expect(() => splitChaptersByChars(const [], 0), throwsArgumentError);
  });
}
