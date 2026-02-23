import 'test_case.dart';

ConformanceTurnResult validateTurn(ConformanceTurn turn, String actualReply) {
  final String expected = turn.expectedReplyContains.trim().toLowerCase();
  final String actual = actualReply.toLowerCase();
  return ConformanceTurnResult(
    turn: turn,
    reply: actualReply,
    passed: expected.isEmpty || actual.contains(expected),
  );
}

ConformanceTestResult validateReplay(
  ConformanceTestCase testCase,
  List<String> replies,
) {
  final List<ConformanceTurnResult> results = <ConformanceTurnResult>[];
  for (int index = 0; index < testCase.turns.length; index += 1) {
    final String reply = index < replies.length ? replies[index] : '';
    results.add(validateTurn(testCase.turns[index], reply));
  }
  return ConformanceTestResult(testCase: testCase, turnResults: results);
}
