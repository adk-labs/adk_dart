import 'test_case.dart';

String generateMarkdownReport(List<ConformanceTestResult> results) {
  final StringBuffer out = StringBuffer();
  out.writeln('# ADK Conformance Report');
  out.writeln();

  for (final ConformanceTestResult result in results) {
    out.writeln('## ${result.testCase.name}');
    out.writeln('- status: ${result.passed ? 'passed' : 'failed'}');
    out.writeln();
    out.writeln('| turn | expected | actual | passed |');
    out.writeln('| --- | --- | --- | --- |');
    for (int index = 0; index < result.turnResults.length; index += 1) {
      final ConformanceTurnResult turnResult = result.turnResults[index];
      out.writeln(
        '| ${index + 1} | ${turnResult.turn.expectedReplyContains} | ${turnResult.reply} | ${turnResult.passed} |',
      );
    }
    out.writeln();
  }

  return out.toString().trimRight();
}
