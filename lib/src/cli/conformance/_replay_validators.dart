/// Validators for replayed CLI conformance turns.
library;

import 'test_case.dart';

/// Validates one replayed turn by matching expected text against [actualReply].
ConformanceTurnResult validateTurn(ConformanceTurn turn, String actualReply) {
  final String expected = turn.expectedReplyContains.trim().toLowerCase();
  final String actual = actualReply.toLowerCase();
  return ConformanceTurnResult(
    turn: turn,
    reply: actualReply,
    passed: expected.isEmpty || actual.contains(expected),
  );
}

/// Validates all replay [replies] for the supplied [testCase].
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
