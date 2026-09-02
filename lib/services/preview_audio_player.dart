import 'package:just_audio/just_audio.dart';

abstract class PreviewAudioPlayer {
  Stream<bool> get playingStream;

  Future<void> setFilePath(String path);

  Future<void> play();

  Future<void> stop();

  Future<void> seekToStart();

  Future<void> dispose();
}

class JustAudioPreviewPlayer implements PreviewAudioPlayer {
  JustAudioPreviewPlayer() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<bool> get playingStream => _player.playerStateStream
      .map((state) =>
          state.playing && state.processingState != ProcessingState.completed)
      .distinct();

  @override
  Future<void> setFilePath(String path) => _player.setFilePath(path);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seekToStart() => _player.seek(Duration.zero);

  @override
  Future<void> dispose() => _player.dispose();
}
