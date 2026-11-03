import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/chapter.dart';
import '../services/text_splitter.dart';

/// Owns the document, text decoding configuration, unit splitting,
/// and per-unit selection independently of the home screen widget tree.
///
/// The screen remains responsible for choosing a file and displaying errors.
class DocumentController {
  DocumentController({List<Chapter> initialChapters = const []})
    : chapters = initialChapters {
    selectAll();
  }

  String? fileName;
  Uint8List? fileBytes;
  String textEncoding = 'auto';
  bool splitByChars = false;
  final TextEditingController charsController = TextEditingController(
    text: '5000',
  );
  List<Chapter> chapters;
  int? selectedIndex;
  final Set<int> checkedUnitIndices = {};

  List<Chapter> get units {
    if (!splitByChars) return chapters;
    final count = int.tryParse(charsController.text);
    if (count == null || count <= 0) return const [];
    return splitChaptersByChars(chapters, count);
  }

  void loadFile(String name, Uint8List bytes, List<Chapter> parsed) {
    fileName = name;
    fileBytes = bytes;
    chapters = parsed;
    selectedIndex = null;
    selectAll();
  }

  void updateDecodedText(String encoding, List<Chapter> parsed) {
    textEncoding = encoding;
    chapters = parsed;
    selectedIndex = null;
    selectAll();
  }

  void selectAll() {
    checkedUnitIndices
      ..clear()
      ..addAll(List.generate(units.length, (index) => index));
  }

  void clearSelection() => checkedUnitIndices.clear();

  void toggleSelection(int index, bool selected) {
    if (selected) {
      checkedUnitIndices.add(index);
    } else {
      checkedUnitIndices.remove(index);
    }
  }

  List<int> get selectedUnitIndices =>
      checkedUnitIndices
          .where((index) => index >= 0 && index < units.length)
          .toList()
        ..sort();

  void dispose() => charsController.dispose();
}
