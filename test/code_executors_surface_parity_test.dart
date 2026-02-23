import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _RecordingExecutor extends BaseCodeExecutor {
  _RecordingExecutor();

  CodeExecutionRequest? lastRequest;

  @override
  Future<CodeExecutionResult> execute(CodeExecutionRequest request) async {
    lastRequest = request;
    return CodeExecutionResult(stdout: 'ok', exitCode: 0);
  }
}

void main() {
  group('code executor surface parity', () {
    test(
      'BaseCodeExecutor defaults and executeCode delegation are stable',
      () async {
        final _RecordingExecutor executor = _RecordingExecutor();

        expect(executor.codeBlockDelimiters, const <(String, String)>[
          ('```tool_code\n', '\n```'),
          ('```python\n', '\n```'),
        ]);
        expect(executor.executionResultDelimiters.$1, '```tool_output\n');
        expect(executor.executionResultDelimiters.$2, '\n```');
        expect(executor.errorRetryAttempts, 2);
        expect(executor.stateful, isFalse);
        expect(executor.optimizeDataFile, isFalse);

        final InvocationContext context = InvocationContext(
          sessionService: InMemorySessionService(),
          invocationId: 'inv_exec_surface',
          agent: Agent(name: 'root', model: 'gemini-2.5-flash'),
          session: Session(id: 's_exec_surface', appName: 'app', userId: 'u1'),
        );

        final CodeExecutionResult result = await executor.executeCode(
          context,
          CodeExecutionInput(code: 'print("hi")'),
        );

        expect(result.exitCode, 0);
        expect(result.stdout, 'ok');
        expect(executor.lastRequest, isNotNull);
        expect(executor.lastRequest!.command, 'print("hi")');
        expect(executor.lastRequest!.workingDirectory, isNull);
      },
    );

    test(
      'BuiltInCodeExecutor aliases UnsafeLocalCodeExecutor behavior',
      () async {
        final BuiltInCodeExecutor executor = BuiltInCodeExecutor(
          defaultTimeout: const Duration(seconds: 2),
        );

        expect(executor, isA<UnsafeLocalCodeExecutor>());

        final CodeExecutionResult result = await executor.execute(
          CodeExecutionRequest(command: 'echo built_in_executor_parity'),
        );

        expect(result.exitCode, 0);
        expect(result.stdout, contains('built_in_executor_parity'));
      },
    );

    test(
      'UnsafeLocalCodeExecutor rejects unsupported stateful/data settings',
      () {
        expect(
          () => UnsafeLocalCodeExecutor(stateful: true),
          throwsArgumentError,
        );
        expect(
          () => UnsafeLocalCodeExecutor(optimizeDataFile: true),
          throwsArgumentError,
        );
      },
    );
  });
}
