import '_replay_validators.dart';
import 'adk_web_server_client.dart';
import 'test_case.dart';

Future<ConformanceTestResult> runConformanceTestCase({
  required AdkWebServerClient client,
  required ConformanceTestCase testCase,
  required String userId,
  required String sessionId,
}) async {
  final List<String> replies = <String>[];
  for (final ConformanceTurn turn in testCase.turns) {
    final Map<String, Object?> response = await client.sendMessage(
      sessionId: sessionId,
      userId: userId,
      text: turn.userText,
    );
    replies.add('${response['reply'] ?? ''}');
  }
  return validateReplay(testCase, replies);
}

Future<List<ConformanceTestResult>> runConformanceSuite({
  required AdkWebServerClient client,
  required List<ConformanceTestCase> testCases,
  required String userId,
  required String sessionId,
}) async {
  final List<ConformanceTestResult> results = <ConformanceTestResult>[];
  for (final ConformanceTestCase testCase in testCases) {
    results.add(
      await runConformanceTestCase(
        client: client,
        testCase: testCase,
        userId: userId,
        sessionId: sessionId,
      ),
    );
  }
  return results;
}
