import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('CloudRunSandboxCodeExecutor', () {
    test('defaults match upstream configuration', () {
      final CloudRunSandboxCodeExecutor executor =
          CloudRunSandboxCodeExecutor();

      expect(executor.stateful, isFalse);
      expect(executor.optimizeDataFile, isFalse);
      expect(executor.sandboxBin, '/usr/local/gcp/bin/sandbox');
      expect(executor.allowEgress, isFalse);
      expect(executor.timeoutSeconds, isNull);
    });

    test('rejects stateful=true', () {
      expect(
        () => CloudRunSandboxCodeExecutor(stateful: true),
        throwsArgumentError,
      );
    });

    test('rejects optimizeDataFile=true', () {
      expect(
        () => CloudRunSandboxCodeExecutor(optimizeDataFile: true),
        throwsArgumentError,
      );
    });

    test('accepts custom sandboxBin, allowEgress and timeoutSeconds', () {
      final CloudRunSandboxCodeExecutor executor = CloudRunSandboxCodeExecutor(
        sandboxBin: '/usr/bin/custom-sandbox',
        allowEgress: true,
        timeoutSeconds: 10,
      );

      expect(executor.sandboxBin, '/usr/bin/custom-sandbox');
      expect(executor.allowEgress, isTrue);
      expect(executor.timeoutSeconds, 10);
    });

    test(
      'reports a clear error when the sandbox binary is not found',
      () async {
        final CloudRunSandboxCodeExecutor executor =
            CloudRunSandboxCodeExecutor(
              sandboxBin: '/nonexistent/sandbox/binary/for/tests',
            );

        final CodeExecutionResult result = await executor.execute(
          CodeExecutionRequest(command: 'print("hello")'),
        );

        expect(result.exitCode, -1);
        expect(result.stdout, isEmpty);
        expect(
          result.stderr,
          contains(
            'Sandbox binary "/nonexistent/sandbox/binary/for/tests" not found',
          ),
        );
      },
    );

    test(
      'executeCode delegates through the same sandbox-launch path',
      () async {
        final CloudRunSandboxCodeExecutor executor =
            CloudRunSandboxCodeExecutor(
              sandboxBin: '/nonexistent/sandbox/binary/for/tests',
            );

        final InvocationContext context = InvocationContext(
          sessionService: InMemorySessionService(),
          invocationId: 'inv_cloud_run_sandbox',
          agent: Agent(name: 'root', model: 'gemini-2.5-flash'),
          session: Session(
            id: 's_cloud_run_sandbox',
            appName: 'app',
            userId: 'u1',
          ),
        );

        final CodeExecutionResult result = await executor.executeCode(
          context,
          CodeExecutionInput(code: 'print("hello")'),
        );

        expect(result.exitCode, -1);
        expect(
          result.stderr,
          contains('Sandbox binary "/nonexistent/sandbox/binary/for/tests"'),
        );
      },
    );
  });
}
