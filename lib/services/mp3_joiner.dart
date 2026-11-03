import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';
import 'package:flutter_lame/flutter_lame.dart';

import '../providers/tts_provider.dart';

/// Streaming MP3 joiner. Keeps only the current decoded PCM segment and
/// LAME's internal state instead of retaining all MP3 clips.
class Mp3JoinSession {
  LameMp3Encoder? _encoder;
  int? _sampleRate;
  int? _channels;
  bool _finished = false;

  Future<Uint8List> add(Uint8List clip) async {
    if (_finished) throw StateError('MP3 join session is finished.');
    try {
      final pcm = decodeMp3(clip);
      if (pcm.frameCount == 0) {
        throw const TtsProviderException(
          'TTS returned an empty audio segment.',
        );
      }
      _sampleRate ??= pcm.sampleRate;
      _channels ??= pcm.channels;
      if (pcm.sampleRate != _sampleRate || pcm.channels != _channels) {
        throw const TtsProviderException(
          'TTS audio segments use different sample rates or channel counts.',
        );
      }
      if (_channels != 1 && _channels != 2) {
        throw const TtsProviderException(
          'Unsupported TTS audio channel count.',
        );
      }
      _encoder ??= LameMp3Encoder(
        sampleRate: _sampleRate!,
        numChannels: _channels!,
        bitRate: 128,
      );
      if (_channels == 1) {
        return await _encoder!.encode(leftChannel: pcm.samples);
      }
      final frames = pcm.frameCount;
      final left = Int16List(frames);
      final right = Int16List(frames);
      for (var i = 0; i < frames; i++) {
        left[i] = pcm.samples[i * 2];
        right[i] = pcm.samples[i * 2 + 1];
      }
      return await _encoder!.encode(leftChannel: left, rightChannel: right);
    } catch (error) {
      if (error is TtsProviderException) rethrow;
      throw TtsProviderException('Could not combine TTS MP3 clips: $error');
    }
  }

  Future<Uint8List> finish() async {
    if (_finished) throw StateError('MP3 join session already finished.');
    _finished = true;
    return _encoder == null ? Uint8List(0) : _encoder!.flush();
  }

  Future<void> close() async {
    _finished = true;
    final encoder = _encoder;
    _encoder = null;
    await encoder?.close();
  }
}

/// Preserve the existing in-memory API for short previews and test helpers.
class Mp3Joiner {
  static Future<Uint8List> join(List<Uint8List> clips) async {
    if (clips.isEmpty) return Uint8List(0);
    if (clips.length == 1) return clips.single;

    final session = Mp3JoinSession();
    final output = BytesBuilder(copy: false);
    try {
      for (final clip in clips) {
        output.add(await session.add(clip));
      }
      output.add(await session.finish());
      return output.takeBytes();
    } finally {
      await session.close();
    }
  }
}
