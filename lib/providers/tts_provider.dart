import 'dart:typed_data';

class VoiceInfo {
  const VoiceInfo({required this.name, required this.locale, this.gender = ''});
  final String name;
  final String locale;
  final String gender;
}

abstract interface class TtsProvider {
  Future<List<VoiceInfo>> listVoices();

  Future<Uint8List> synthesize(
    String text,
    String voice, {
    double rate = 1,
    double volume = 0,
    double pitch = 0,
  });
}

/// Optional lifecycle contract for providers that own a network client.
/// Device and Edge providers already manage per-operation resources.
abstract interface class ClosableTtsProvider {
  void close();
}

void closeTtsProvider(TtsProvider provider) {
  if (provider is ClosableTtsProvider) {
    (provider as ClosableTtsProvider).close();
  }
}

class TtsProviderException implements Exception {
  const TtsProviderException(this.message);
  final String message;
  @override
  String toString() => message;
}
