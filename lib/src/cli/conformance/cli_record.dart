import '../plugins/recordings_plugin.dart';
import '../plugins/recordings_schema.dart';
import 'adk_web_server_client.dart';
import 'test_case.dart';

Future<SessionRecording> recordConformanceSession({
  required AdkWebServerClient client,
  required String appName,
  required String userId,
  required String sessionId,
  required List<ConformanceTurn> turns,
}) async {
  final RecordingsPlugin plugin = RecordingsPlugin();
  final SessionRecording recording = plugin.startSession(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
  );

  for (final ConformanceTurn turn in turns) {
    final Map<String, Object?> response = await client.sendMessage(
      sessionId: sessionId,
      userId: userId,
      text: turn.userText,
    );
    final String reply = '${response['reply'] ?? ''}';
    plugin.appendTurn(
      sessionId: sessionId,
      turn: RecordingTurn(
        userText: turn.userText,
        replyText: reply,
        metadata: <String, Object?>{
          'expected_reply_contains': turn.expectedReplyContains,
        },
      ),
    );
  }
  return recording;
}
