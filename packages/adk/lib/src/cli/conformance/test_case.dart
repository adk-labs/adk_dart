/// Data models for CLI conformance recording and replay tests.
library;

/// One conversational turn in a conformance test.
class ConformanceTurn {
  /// Creates a conformance turn.
  ConformanceTurn({
    required this.userText,
    required this.expectedReplyContains,
  });

  /// User message sent to the agent.
  final String userText;

  /// Substring that should appear in the agent reply.
  final String expectedReplyContains;
}

/// Named conformance test case with ordered turns.
class ConformanceTestCase {
  /// Creates a conformance test case.
  ConformanceTestCase({required this.name, required this.turns});

  /// Human-readable test name.
  final String name;

  /// Ordered turns to replay.
  final List<ConformanceTurn> turns;
}

/// Result for one replayed turn.
class ConformanceTurnResult {
  /// Creates a turn result.
  ConformanceTurnResult({
    required this.turn,
    required this.reply,
    required this.passed,
  });

  /// Original turn definition.
  final ConformanceTurn turn;

  /// Actual agent reply.
  final String reply;

  /// Whether this turn met expectations.
  final bool passed;
}

/// Aggregate result for one conformance test case.
class ConformanceTestResult {
  /// Creates a conformance test result.
  ConformanceTestResult({required this.testCase, required this.turnResults});

  /// Source test case metadata.
  final ConformanceTestCase testCase;

  /// Per-turn replay results.
  final List<ConformanceTurnResult> turnResults;

  /// Whether every turn in this test case passed.
  bool get passed =>
      turnResults.every((ConformanceTurnResult item) => item.passed);
}
