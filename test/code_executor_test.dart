import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('UnsafeLocalCodeExecutor', () {
    test('runs a shell command and captures stdout', () async {
      final UnsafeLocalCodeExecutor executor = UnsafeLocalCodeExecutor();
      final CodeExecutionResult result = await executor.execute(
        CodeExecutionRequest(command: 'echo hello'),
      );

      expect(result.isSuccess, isTrue);
      expect(result.stdout.toLowerCase(), contains('hello'));
    });
  });
}
