import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';
import 'package:flutter_lame/flutter_lame.dart';

import '../providers/tts_provider.dart';

/// Decode each independently encoded MP3 clip to PCM and encode a single MP3
/// stream. This avoids concatenating multiple ID3/Xing headers and independent
/// MP3 encoder streams in one output file.
class Mp3Joiner {
  static Future<Uint8List> join(List<Uint8List> clips) async {
    if (clips.isEmpty) return Uint8List(0);
    if (clips.length == 1) return clips.single;

    LameMp3Encoder? encoder;
    final output = BytesBuilder(copy: false);
    int? sampleRate;
    int? channels;
    try {
      for (final clip in clips) {
        final pcm = decodeMp3(clip);
        if (pcm.frameCount == 0) {
          throw const TtsProviderException(
            'TTS returned an empty audio segment.',
          );
        }
        sampleRate ??= pcm.sampleRate;
        channels ??= pcm.channels;
        if (pcm.sampleRate != sampleRate || pcm.channels != channels) {
          throw const TtsProviderException(
            'TTS audio segments use different sample rates or channel counts.',
          );
        }
        if (channels != 1 && channels != 2) {
          throw const TtsProviderException(
            'Unsupported TTS audio channel count.',
          );
        }
        encoder ??= LameMp3Encoder(
          sampleRate: sampleRate,
          numChannels: channels,
          bitRate: 128,
        );
        final interleaved = pcm.samples;
        if (channels == 1) {
          output.add(await encoder.encode(leftChannel: interleaved));
        } else {
          final frames = pcm.frameCount;
          final left = Int16List(frames);
          final right = Int16List(frames);
          for (var i = 0; i < frames; i++) {
            left[i] = interleaved[i * 2];
            right[i] = interleaved[i * 2 + 1];
          }
          output.add(
            await encoder.encode(leftChannel: left, rightChannel: right),
          );
        }
      }
      output.add(await encoder!.flush());
      return output.takeBytes();
    } catch (error) {
      if (error is TtsProviderException) rethrow;
      throw TtsProviderException('Could not combine TTS MP3 clips: $error');
    } finally {
      await encoder?.close();
    }
  }
}
