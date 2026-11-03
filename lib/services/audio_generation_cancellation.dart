/// Cooperative cancellation is checked between TTS requests and before
/// publishing each completed MP3. An in-flight native/cloud operation may
/// still finish; cancellation prevents its result from being published.
class AudioGenerationCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const AudioGenerationCancelled();
  }
}

class AudioGenerationCancelled implements Exception {
  const AudioGenerationCancelled();

  @override
  String toString() => 'MP3 generation was cancelled.';
}
