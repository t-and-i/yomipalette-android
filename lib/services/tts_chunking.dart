import 'dart:convert';

/// Conservative, app-side thresholds. Google publishes a total request byte
/// limit, but does not guarantee a specific maximum sentence length.
class TtsChunkPolicy {
  const TtsChunkPolicy({required this.maxChars, required this.maxUtf8Bytes});

  final int maxChars;
  final int maxUtf8Bytes;

  static TtsChunkPolicy forVoice(String providerName, String voice) {
    if (providerName != 'google') {
      return const TtsChunkPolicy(maxChars: 1800, maxUtf8Bytes: 4500);
    }
    final name = voice.toLowerCase();
    if (name.contains('-chirp3-hd-')) {
      return const TtsChunkPolicy(maxChars: 90, maxUtf8Bytes: 600);
    }
    if (name.contains('-neural2-') || name.contains('-studio-')) {
      return const TtsChunkPolicy(maxChars: 450, maxUtf8Bytes: 3500);
    }
    if (name.contains('-standard-') || name.contains('-wavenet-')) {
      return const TtsChunkPolicy(maxChars: 1000, maxUtf8Bytes: 4000);
    }
    return const TtsChunkPolicy(maxChars: 450, maxUtf8Bytes: 3500);
  }

  TtsChunkPolicy smaller() => TtsChunkPolicy(
    maxChars: (maxChars ~/ 2).clamp(12, maxChars),
    maxUtf8Bytes: (maxUtf8Bytes ~/ 2).clamp(64, maxUtf8Bytes),
  );
}

/// Preserve all characters, including surrogate pairs, spaces and punctuation.
/// Sentence-ending punctuation is preferred; whitespace and commas are used
/// for otherwise unpunctuated sentences.
List<String> splitTtsText(String text, TtsChunkPolicy policy) {
  if (text.isEmpty) return const [];
  final runes = text.runes.toList();
  final chunks = <String>[];
  var start = 0;
  while (start < runes.length) {
    var end = start;
    var bytes = 0;
    while (end < runes.length && end - start < policy.maxChars) {
      final size = utf8.encode(String.fromCharCode(runes[end])).length;
      if (bytes + size > policy.maxUtf8Bytes) break;
      bytes += size;
      end++;
    }
    if (end == start) {
      throw StateError('TTS chunk policy must allow at least one character.');
    }
    if (end < runes.length) {
      var bestSentence = -1;
      var bestSoft = -1;
      for (var i = start; i < end; i++) {
        final char = String.fromCharCode(runes[i]);
        if ('。．！？!?\n'.contains(char)) bestSentence = i + 1;
        if ('、，,；; \t\r'.contains(char)) bestSoft = i + 1;
      }
      final minUseful = start + ((end - start) * 0.35).floor();
      if (bestSentence >= minUseful) {
        end = bestSentence;
      } else if (bestSoft >= minUseful) {
        end = bestSoft;
      }
    }
    chunks.add(String.fromCharCodes(runes.sublist(start, end)));
    start = end;
  }
  return chunks;
}

/// A long-sentence INVALID_ARGUMENT can be addressed by splitting.
/// Authentication, quota, billing, permissions and other errors must stop.
bool isSentenceTooLongError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('invalid_argument') &&
      (message.contains('sentences that are too long') ||
          message.contains('sentence') && message.contains('too long'));
}
