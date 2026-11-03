import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tts_text_mp3_mobile/controllers/document_controller.dart';
import 'package:tts_text_mp3_mobile/models/chapter.dart';

void main() {
  const chapters = [
    Chapter(index: 1, title: 'Part 1', text: 'abcdefghij'),
    Chapter(index: 2, title: 'Part 2', text: 'klmnopqrst'),
  ];

  test('initial selection includes each chapter', () {
    final controller = DocumentController(initialChapters: chapters);
    addTearDown(controller.dispose);

    expect(controller.units, hasLength(2));
    expect(controller.checkedUnitIndices, {0, 1});
    expect(controller.selectedUnitIndices, [0, 1]);
  });

  test('text splitting and invalid maxChars preserve selection semantics', () {
    final controller = DocumentController(initialChapters: chapters);
    addTearDown(controller.dispose);

    controller.splitByChars = true;
    controller.charsController.text = '5';
    expect(controller.units.length, 4);
    controller.selectAll();
    expect(controller.selectedUnitIndices, [0, 1, 2, 3]);

    controller.toggleSelection(1, false);
    controller.checkedUnitIndices.add(1234);
    expect(controller.selectedUnitIndices, [0, 2, 3]);

    controller.charsController.text = 'not-a-number';
    expect(controller.units, isEmpty);
    expect(controller.selectedUnitIndices, isEmpty);
  });

  test('importing a new document resets stale checks and selected index', () {
    final controller = DocumentController(initialChapters: chapters);
    addTearDown(controller.dispose);

    controller.checkedUnitIndices.clear();
    controller.selectedIndex = 1;
    final bytes = Uint8List.fromList([65, 66, 67]);
    controller.loadFile('fresh.txt', bytes, const [
      Chapter(index: 1, title: 'Fresh', text: 'Hello'),
    ]);

    expect(controller.fileName, 'fresh.txt');
    expect(controller.fileBytes, bytes);
    expect(controller.selectedIndex, isNull);
    expect(controller.checkedUnitIndices, {0});
  });

  test('changing the encoding updates document without changing the file', () {
    final controller = DocumentController(initialChapters: chapters);
    addTearDown(controller.dispose);
    controller.loadFile('source.txt', Uint8List.fromList([49]), chapters);
    controller.selectedIndex = 1;
    controller.updateDecodedText('utf-8', const [
      Chapter(index: 1, title: 'One', text: 'abc'),
    ]);
    expect(controller.textEncoding, 'utf-8');
    expect(controller.fileName, 'source.txt');
    expect(controller.selectedIndex, isNull);
    expect(controller.checkedUnitIndices, {0});
  });
}
