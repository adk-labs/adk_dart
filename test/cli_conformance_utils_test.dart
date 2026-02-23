import 'package:adk_dart/src/cli/conformance/_generate_markdown_utils.dart';
import 'package:adk_dart/src/cli/conformance/_replay_validators.dart';
import 'package:adk_dart/src/cli/conformance/test_case.dart';
import 'package:test/test.dart';

void main() {
  group('conformance utilities', () {
    test('validate replay and generate markdown', () {
      final ConformanceTestCase testCase = ConformanceTestCase(
        name: 'smoke',
        turns: <ConformanceTurn>[
          ConformanceTurn(userText: 'hello', expectedReplyContains: 'hi'),
        ],
      );
      final ConformanceTestResult result = validateReplay(testCase, <String>[
        'hi there',
      ]);

      expect(result.passed, isTrue);
      final String markdown = generateMarkdownReport(<ConformanceTestResult>[
        result,
      ]);
      expect(markdown, contains('# ADK Conformance Report'));
      expect(markdown, contains('smoke'));
    });
  });
}
