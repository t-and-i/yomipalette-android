import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'epub_reader.dart';

import '../models/chapter.dart';

class DocumentReader {
  static const textEncodings = <String>[
    'auto',
    'utf-8',
    'utf-16le',
    'utf-16be',
    'utf-32le',
    'utf-32be',
    'shift_jis',
    'gb18030',
    'big5',
  ];

  static Future<List<Chapter>> read(
    String name,
    Uint8List bytes, {
    String textEncoding = 'auto',
  }) async {
    final lower = name.toLowerCase();
    if (lower.endsWith('.txt')) {
      return _readText(name, bytes, textEncoding);
    }
    if (lower.endsWith('.epub')) return readEpubSections(bytes);
    throw const FormatException('Only TXT and EPUB files are supported.');
  }

  static Future<List<Chapter>> _readText(
    String name,
    Uint8List bytes,
    String textEncoding,
  ) async {
    final text = await decodeText(bytes, textEncoding);
    final title = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return [Chapter(index: 1, title: title, text: _clean(text))];
  }

  static Future<String> decodeText(
    Uint8List bytes, [
    String textEncoding = 'auto',
  ]) async {
    final encoding = textEncoding.toLowerCase();
    if (!textEncodings.contains(encoding)) {
      throw FormatException('Unsupported text encoding: $textEncoding');
    }
    if (encoding != 'auto') return _decode(bytes, encoding);

    final bom = _bomEncoding(bytes);
    if (bom != null) return _decode(bytes, bom);

    final utf16 = _probableUtf16(bytes);
    if (utf16 != null) return _decode(bytes, utf16);

    try {
      return utf8.decode(bytes);
    } on FormatException {
      // Continue with legacy encodings.
    }

    String? best;
    var bestScore = -1 << 30;
    for (final candidate in const ['shift_jis', 'gb18030', 'big5']) {
      try {
        final decoded = await _decode(bytes, candidate);
        final score = _textQuality(decoded, candidate);
        if (score > bestScore) {
          best = decoded;
          bestScore = score;
        }
      } catch (_) {
        // The native converter may not expose every charset on every OS.
      }
    }
    if (best != null) return best;
    return latin1.decode(bytes);
  }

  static Future<String> _decode(Uint8List bytes, String encoding) async {
    switch (encoding) {
      case 'utf-8':
        final offset = _startsWith(bytes, const [0xef, 0xbb, 0xbf]) ? 3 : 0;
        return utf8.decode(bytes.sublist(offset));
      case 'utf-16le':
        return _decodeUtf16(bytes, littleEndian: true);
      case 'utf-16be':
        return _decodeUtf16(bytes, littleEndian: false);
      case 'utf-32le':
        return _decodeUtf32(bytes, littleEndian: true);
      case 'utf-32be':
        return _decodeUtf32(bytes, littleEndian: false);
      case 'shift_jis':
        return _decodeLegacy(
            bytes, const ['windows-31j', 'MS932', 'Shift_JIS']);
      case 'gb18030':
        return _decodeLegacy(bytes, const ['GB18030', 'GBK']);
      case 'big5':
        return _decodeLegacy(bytes, const ['Big5']);
    }
    throw FormatException('Unsupported text encoding: $encoding');
  }

  static Future<String> _decodeLegacy(
    Uint8List bytes,
    List<String> aliases,
  ) async {
    Object? lastError;
    for (final alias in aliases) {
      try {
        return await CharsetConverter.decode(alias, bytes);
      } catch (error) {
        lastError = error;
      }
    }
    throw FormatException('Character encoding is unavailable: $lastError');
  }

  static String? _bomEncoding(Uint8List bytes) {
    if (_startsWith(bytes, const [0xef, 0xbb, 0xbf])) return 'utf-8';
    if (_startsWith(bytes, const [0xff, 0xfe, 0x00, 0x00])) return 'utf-32le';
    if (_startsWith(bytes, const [0x00, 0x00, 0xfe, 0xff])) return 'utf-32be';
    if (_startsWith(bytes, const [0xff, 0xfe])) return 'utf-16le';
    if (_startsWith(bytes, const [0xfe, 0xff])) return 'utf-16be';
    return null;
  }

  static String? _probableUtf16(Uint8List bytes) {
    if (bytes.length < 4) return null;
    var evenNulls = 0;
    var oddNulls = 0;
    for (var index = 0; index < bytes.length; index++) {
      if (bytes[index] == 0) {
        index.isEven ? evenNulls++ : oddNulls++;
      }
    }
    final pairs = bytes.length ~/ 2;
    if (oddNulls > pairs * 0.35 && evenNulls < pairs * 0.1) {
      return 'utf-16le';
    }
    if (evenNulls > pairs * 0.35 && oddNulls < pairs * 0.1) {
      return 'utf-16be';
    }
    return null;
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    var offset = 0;
    if (_startsWith(
        bytes, littleEndian ? const [0xff, 0xfe] : const [0xfe, 0xff])) {
      offset = 2;
    }
    if ((bytes.length - offset).isOdd) {
      throw const FormatException('Invalid UTF-16 text.');
    }
    final units = <int>[];
    for (var index = offset; index < bytes.length; index += 2) {
      units.add(littleEndian
          ? bytes[index] | (bytes[index + 1] << 8)
          : (bytes[index] << 8) | bytes[index + 1]);
    }
    return String.fromCharCodes(units);
  }

  static String _decodeUtf32(Uint8List bytes, {required bool littleEndian}) {
    var offset = 0;
    final bom = littleEndian
        ? const [0xff, 0xfe, 0x00, 0x00]
        : const [0x00, 0x00, 0xfe, 0xff];
    if (_startsWith(bytes, bom)) offset = 4;
    if ((bytes.length - offset) % 4 != 0) {
      throw const FormatException('Invalid UTF-32 text.');
    }
    final runes = <int>[];
    for (var index = offset; index < bytes.length; index += 4) {
      final rune = littleEndian
          ? bytes[index] |
              (bytes[index + 1] << 8) |
              (bytes[index + 2] << 16) |
              (bytes[index + 3] << 24)
          : (bytes[index] << 24) |
              (bytes[index + 1] << 16) |
              (bytes[index + 2] << 8) |
              bytes[index + 3];
      if (rune < 0 || rune > 0x10ffff || (rune >= 0xd800 && rune <= 0xdfff)) {
        throw const FormatException('Invalid UTF-32 text.');
      }
      runes.add(rune);
    }
    return String.fromCharCodes(runes);
  }

  static int _textQuality(String text, String encoding) {
    var score = 0;
    for (final rune in text.runes) {
      if (rune == 0xfffd || rune == 0) score -= 100;
      if ((rune < 0x20 && rune != 0x09 && rune != 0x0a && rune != 0x0d) ||
          (rune >= 0x7f && rune <= 0x9f)) {
        score -= 30;
      }
      if ((rune >= 0x3040 && rune <= 0x30ff) ||
          (rune >= 0xff65 && rune <= 0xff9f)) {
        score += encoding == 'shift_jis' ? 3 : 1;
      }
      if (rune == 0x3001 || rune == 0x3002) score += 2;
    }
    return score;
  }

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (bytes[index] != prefix[index]) return false;
    }
    return true;
  }

  static String _clean(String text) => text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' ?\n ?'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
