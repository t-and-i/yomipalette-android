import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_edge_tts/flutter_edge_tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_text_mp3_mobile/models/chapter.dart';
import 'package:tts_text_mp3_mobile/providers/edge_provider.dart';
import 'package:tts_text_mp3_mobile/providers/tts_provider.dart';
import 'package:tts_text_mp3_mobile/services/audio_generator.dart';

void main() {
  test(
    'interrupted Edge audio stays unfinished and resumes from that unit',
    () async {
      final clip = await File('test/fixtures/audio/tone.mp3').readAsBytes();
      final directory = await Directory.systemTemp.createTemp('edge-resume-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      addTearDown(() async {
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
        await directory.delete(recursive: true);
      });
      var requests = 0;
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((message) {
          if (message is! String || !message.contains('Path:ssml')) return;
          requests++;
          final interrupted = requests == 2;
          final bytes = interrupted ? clip.sublist(0, clip.length ~/ 2) : clip;
          socket.add(
            Uint8List.fromList([...utf8.encode('Path:audio\r\n'), ...bytes]),
          );
          if (interrupted) {
            // A graceful transport close still means incomplete synthesis when
            // the service did not send its protocol completion message.
            socket.close(WebSocketStatus.normalClosure);
          } else {
            socket.add('Path:turn.end\r\n\r\n');
          }
        });
      });
      final provider = EdgeProvider(
        clientFactory: (voice) => FlutterEdgeTts(
          voice: voice,
          webSocketConnector: () =>
              WebSocket.connect('ws://127.0.0.1:${server.port}'),
        ),
      );
      const units = [
        Chapter(index: 1, title: 'first', text: 'First complete unit.'),
        Chapter(index: 2, title: 'second', text: 'Second interrupted unit.'),
      ];
      final completed = <String>[];
      await expectLater(
        AudioGenerator.generateAll(
          provider,
          units,
          'ja-JP-KeitaNeural',
          outputDirectory: directory.path,
          onFileGenerated: (file, _, _) => completed.add(file),
        ),
        throwsA(isA<TtsProviderException>()),
      );
      expect(completed, hasLength(1));
      expect(await File(completed.single).readAsBytes(), clip);
      expect(await File('${directory.path}/002_second.mp3').exists(), isFalse);
      final firstModified = await File(completed.single).lastModified();
      final result = await AudioGenerator.generateAll(
        provider,
        // HomeScreen resumes with only the still-checked, unfinished units.
        units.sublist(1),
        'ja-JP-KeitaNeural',
        outputDirectory: directory.path,
        existingPaths: completed,
      );
      expect(result, hasLength(2));
      expect(await File(result.last).readAsBytes(), clip);
      expect(await File(completed.single).lastModified(), firstModified);
      expect(directory.listSync().whereType<Directory>(), isEmpty);
    },
  );
}
