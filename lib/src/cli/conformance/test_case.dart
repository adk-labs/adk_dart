class ConformanceTurn {
  ConformanceTurn({
    required this.userText,
    required this.expectedReplyContains,
  });

  final String userText;
  final String expectedReplyContains;
}

class ConformanceTestCase {
  ConformanceTestCase({required this.name, required this.turns});

  final String name;
  final List<ConformanceTurn> turns;
}

class ConformanceTurnResult {
  ConformanceTurnResult({
    required this.turn,
    required this.reply,
    required this.passed,
  });

  final ConformanceTurn turn;
  final String reply;
  final bool passed;
}

class ConformanceTestResult {
  ConformanceTestResult({required this.testCase, required this.turnResults});

  final ConformanceTestCase testCase;
  final List<ConformanceTurnResult> turnResults;

  bool get passed =>
      turnResults.every((ConformanceTurnResult item) => item.passed);
}
