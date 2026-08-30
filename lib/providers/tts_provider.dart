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

class TtsProviderException implements Exception {
  const TtsProviderException(this.message);
  final String message;
  @override
  String toString() => message;
}
