import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('recordings plugin', () {
    test('saves and loads recordings', () async {
      final RecordingsPlugin plugin = RecordingsPlugin();
      final SessionRecording session = plugin.startSession(
        appName: 'app',
        userId: 'user',
        sessionId: 'session',
      );
      plugin.appendTurn(
        sessionId: session.sessionId,
        turn: RecordingTurn(userText: 'hello', replyText: 'hi'),
      );

      final Directory temp = Directory.systemTemp.createTempSync('adk_rec_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final String filePath = '${temp.path}${Platform.pathSeparator}rec.json';
      await plugin.saveToFile(filePath);

      final RecordingsPlugin loaded = await RecordingsPlugin.loadFromFile(
        filePath,
      );
      expect(loaded.recordings, hasLength(1));
      expect(loaded.recordings.first.turns.first.replyText, 'hi');
    });

    test('replay plugin iterates turns', () {
      final SessionRecording recording = SessionRecording(
        appName: 'app',
        userId: 'user',
        sessionId: 'session',
        turns: <RecordingTurn>[
          RecordingTurn(userText: 'a', replyText: 'A'),
          RecordingTurn(userText: 'b', replyText: 'B'),
        ],
      );
      final ReplayPlugin replay = ReplayPlugin(recording);

      expect(replay.hasNext, isTrue);
      expect(replay.nextTurn()!.replyText, 'A');
      expect(replay.nextTurn()!.replyText, 'B');
      expect(replay.hasNext, isFalse);
    });
  });
}
