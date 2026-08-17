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

    test('executes Dart code using local Dart runtime', () async {
      final UnsafeLocalCodeExecutor executor = UnsafeLocalCodeExecutor(executable: 'dart');
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
        sessionId: 's1',
      );
      final InvocationContext invocationContext = InvocationContext(
        invocationId: 'inv1',
        agent: Agent(name: 'code_agent'),
        session: session,
        sessionService: sessionService,
      );

      final CodeExecutionResult result = await executor.executeCode(
        invocationContext,
        CodeExecutionInput(
          code: 'void main() { print("Hello from Dart Code Executor! 42 + 58 = ${42 + 58}"); }',
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.stdout, contains('Hello from Dart Code Executor! 42 + 58 = 100'));
    });

    test('executes Python code when specified', () async {
      final UnsafeLocalCodeExecutor executor = UnsafeLocalCodeExecutor(executable: 'python3');
      final InMemorySessionService sessionService = InMemorySessionService();
      final Session session = await sessionService.createSession(
        appName: 'app',
        userId: 'user',
        sessionId: 's2',
      );
      final InvocationContext invocationContext = InvocationContext(
        invocationId: 'inv2',
        agent: Agent(name: 'py_agent'),
        session: session,
        sessionService: sessionService,
      );

      final CodeExecutionResult result = await executor.executeCode(
        invocationContext,
        CodeExecutionInput(
          code: 'print("Python result:", 10 * 10)',
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.stdout, contains('Python result: 100'));
    });
  });
}
