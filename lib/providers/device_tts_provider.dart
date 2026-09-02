import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_lame/flutter_lame.dart';

import 'tts_provider.dart';

class DeviceTtsEngine {
  const DeviceTtsEngine({
    required this.name,
    required this.label,
    required this.isDefault,
  });

  final String name;
  final String label;
  final bool isDefault;

  static DeviceTtsEngine fromMap(Map<Object?, Object?> map) => DeviceTtsEngine(
        name: map['name']! as String,
        label: map['label']! as String,
        isDefault: map['isDefault'] as bool? ?? false,
      );
}

class DeviceTtsProvider implements TtsProvider {
  DeviceTtsProvider(this.engineName, {MethodChannel? channel})
      : _channel = channel ?? _defaultChannel;

  static const _defaultChannel = MethodChannel('tts_text_mp3/device_tts');
  final String engineName;
  final MethodChannel _channel;

  static Future<List<DeviceTtsEngine>> listEngines(
      {MethodChannel? channel}) async {
    final values = await (channel ?? _defaultChannel)
            .invokeListMethod<Object?>('listEngines') ??
        const [];
    return values
        .map((value) =>
            DeviceTtsEngine.fromMap(Map<Object?, Object?>.from(value! as Map)))
        .toList(growable: false);
  }

  @override
  Future<List<VoiceInfo>> listVoices() async {
    final values = await _channel.invokeListMethod<Object?>('listVoices', {
          'engine': engineName,
        }) ??
        const [];
    return values.map((value) {
      final map = Map<Object?, Object?>.from(value! as Map);
      return VoiceInfo(
        name: map['name']! as String,
        locale: map['locale']! as String,
        gender: map['networkRequired'] == true ? 'Network' : 'On-device',
      );
    }).toList(growable: false);
  }

  @override
  Future<Uint8List> synthesize(
    String text,
    String voice, {
    double rate = 1,
    double volume = 0,
    double pitch = 0,
  }) async {
    try {
      final wav = await _channel.invokeMethod<Uint8List>('synthesize', {
        'engine': engineName,
        'voice': voice,
        'text': text,
        'rate': rate,
        'volume': ((100 + volume) / 100).clamp(0.0, 1.0),
        'pitch': (1 + pitch / 100).clamp(0.5, 2.0),
      });
      if (wav == null || wav.isEmpty) {
        throw const TtsProviderException(
            'The device TTS engine returned no audio.');
      }
      return await _wavToMp3(wav);
    } on PlatformException catch (error) {
      throw TtsProviderException(error.message ?? 'Device TTS failed.');
    }
  }

  static Future<Uint8List> _wavToMp3(Uint8List wav) async {
    final audio = _PcmWave.parse(wav);
    final encoder = LameMp3Encoder(
      sampleRate: audio.sampleRate,
      numChannels: audio.channels,
      bitRate: 128,
    );
    try {
      final frames = BytesBuilder(copy: false);
      frames.add(await encoder.encode(
        leftChannel: audio.left,
        rightChannel: audio.right,
      ));
      frames.add(await encoder.flush());
      return frames.takeBytes();
    } finally {
      await encoder.close();
    }
  }
}

class _PcmWave {
  const _PcmWave({
    required this.sampleRate,
    required this.channels,
    required this.left,
    this.right,
  });

  final int sampleRate;
  final int channels;
  final Int16List left;
  final Int16List? right;

  static _PcmWave parse(Uint8List bytes) {
    if (bytes.length < 44 ||
        _ascii(bytes, 0, 4) != 'RIFF' ||
        _ascii(bytes, 8, 4) != 'WAVE') {
      throw const TtsProviderException(
          'The device TTS engine returned an unsupported audio format.');
    }
    final data = ByteData.sublistView(bytes);
    var offset = 12;
    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? audioFormat;
    int? pcmOffset;
    int? pcmLength;
    while (offset + 8 <= bytes.length) {
      final id = _ascii(bytes, offset, 4);
      final length = data.getUint32(offset + 4, Endian.little);
      final content = offset + 8;
      if (content + length > bytes.length) break;
      if (id == 'fmt ' && length >= 16) {
        audioFormat = data.getUint16(content, Endian.little);
        channels = data.getUint16(content + 2, Endian.little);
        sampleRate = data.getUint32(content + 4, Endian.little);
        bitsPerSample = data.getUint16(content + 14, Endian.little);
      } else if (id == 'data') {
        pcmOffset = content;
        pcmLength = length;
      }
      offset = content + length + (length.isOdd ? 1 : 0);
    }
    if (audioFormat != 1 ||
        (channels != 1 && channels != 2) ||
        bitsPerSample != 16 ||
        sampleRate == null ||
        pcmOffset == null ||
        pcmLength == null) {
      throw const TtsProviderException(
          'Device TTS must provide mono or stereo 16-bit PCM WAV audio.');
    }
    final frameCount = pcmLength ~/ (channels! * 2);
    final left = Int16List(frameCount);
    final right = channels == 2 ? Int16List(frameCount) : null;
    for (var frame = 0; frame < frameCount; frame++) {
      final base = pcmOffset + frame * channels * 2;
      left[frame] = data.getInt16(base, Endian.little);
      if (right != null) right[frame] = data.getInt16(base + 2, Endian.little);
    }
    return _PcmWave(
      sampleRate: math.max(8000, sampleRate),
      channels: channels,
      left: left,
      right: right,
    );
  }

  static String _ascii(Uint8List bytes, int offset, int length) =>
      String.fromCharCodes(bytes.sublist(offset, offset + length));
}
