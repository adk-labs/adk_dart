import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) {
    return const Stream<LlmResponse>.empty();
  }
}

Future<InvocationContext> _buildInvocationContext() async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'app',
    userId: 'user',
    sessionId: 'session',
  );

  return InvocationContext(
    sessionService: sessionService,
    invocationId: 'invocation_1',
    agent: Agent(name: 'root_agent', model: _NoopModel()),
    session: session,
  );
}

void main() {
  group('code execution utils', () {
    test('getEncodedFileContent keeps base64 and encodes plain bytes', () {
      final List<int> plain = utf8.encode('hello');
      final List<int> encoded = CodeExecutionUtils.getEncodedFileContent(plain);
      expect(utf8.decode(encoded), base64Encode(plain));

      final List<int> already = utf8.encode(base64Encode(utf8.encode('x')));
      final List<int> kept = CodeExecutionUtils.getEncodedFileContent(already);
      expect(utf8.decode(kept), utf8.decode(already));
    });

    test(
      'extractCodeAndTruncateContent converts text block to executable part',
      () {
        final Content content = Content(
          role: 'model',
          parts: <Part>[
            Part.text('prefix\\n```python\\nprint(1)\\n```\\nsuffix'),
          ],
        );

        final String? code = CodeExecutionUtils.extractCodeAndTruncateContent(
          content,
          const <(String, String)>[('```python\\n', '\\n```')],
        );

        expect(code, 'print(1)');
        expect(content.parts, hasLength(2));
        expect(content.parts[0].text, contains('prefix'));
        expect((content.parts[1].executableCode as Map)['code'], 'print(1)');
      },
    );

    test('buildCodeExecutionResultPart encodes success and failure', () {
      final Part failed = CodeExecutionUtils.buildCodeExecutionResultPart(
        CodeExecutionResult(stderr: 'boom', exitCode: 1),
      );
      expect((failed.codeExecutionResult as Map)['outcome'], 'OUTCOME_FAILED');

      final Part success = CodeExecutionUtils.buildCodeExecutionResultPart(
        CodeExecutionResult(stdout: 'ok'),
      );
      expect((success.codeExecutionResult as Map)['outcome'], 'OUTCOME_OK');
    });

    test('convertCodeExecutionParts rewrites trailing code/result parts', () {
      final Content executable = Content(
        role: 'model',
        parts: <Part>[CodeExecutionUtils.buildExecutableCodePart('print(1)')],
      );

      CodeExecutionUtils.convertCodeExecutionParts(
        executable,
        ('```tool_code\\n', '\\n```'),
        ('```tool_output\\n', '\\n```'),
      );
      expect(executable.parts.single.text, contains('```tool_code'));

      final Content result = Content(
        role: 'model',
        parts: <Part>[
          Part(
            codeExecutionResult: <String, Object?>{
              'outcome': 'OUTCOME_OK',
              'output': 'hello',
            },
          ),
        ],
      );
      CodeExecutionUtils.convertCodeExecutionParts(
        result,
        ('```tool_code\\n', '\\n```'),
        ('```tool_output\\n', '\\n```'),
      );
      expect(result.role, 'user');
      expect(result.parts.single.text, contains('hello'));
    });
  });

  group('code executor context', () {
    test('tracks execution id, files, and error counts', () {
      final Map<String, Object?> state = <String, Object?>{};
      final CodeExecutorContext context = CodeExecutorContext(state);

      expect(context.getExecutionId(), isNull);
      context.setExecutionId('exec_1');
      expect(context.getExecutionId(), 'exec_1');

      context.addInputFiles(<CodeExecutionFile>[
        CodeExecutionFile(name: 'input.csv', content: 'a,b\\n1,2'),
      ]);
      expect(context.getInputFiles(), hasLength(1));

      context.addProcessedFileNames(<String>['input.csv']);
      expect(context.getProcessedFileNames(), contains('input.csv'));

      expect(context.getErrorCount('inv'), 0);
      context.incrementErrorCount('inv');
      context.incrementErrorCount('inv');
      expect(context.getErrorCount('inv'), 2);
      context.resetErrorCount('inv');
      expect(context.getErrorCount('inv'), 0);

      context.updateCodeExecutionResult('inv', 'print(1)', '1', '');
      expect(state['_code_execution_results'], isA<Map>());

      final Map<String, Object?> delta = context.getStateDelta();
      expect(delta.containsKey('_code_execution_context'), isTrue);

      context.clearInputFiles();
      expect(context.getInputFiles(), isEmpty);
      expect(context.getProcessedFileNames(), isEmpty);
    });
  });

  group('executors', () {
    test(
      'unsafe local executor executes Python code via executeCode',
      () async {
        final InvocationContext invocationContext =
            await _buildInvocationContext();
        final UnsafeLocalCodeExecutor executor = UnsafeLocalCodeExecutor();
        final CodeExecutionResult result = await executor.executeCode(
          invocationContext,
          CodeExecutionInput(code: 'print("hello")'),
        );

        expect(result.stderr, isEmpty);
        expect(result.stdout.toLowerCase(), contains('hello'));
      },
    );

    test('container executor validates required config', () {
      expect(
        () => ContainerCodeExecutor(image: null, dockerPath: null),
        throwsArgumentError,
      );
    });

    test('gke manifest contains hardened settings', () async {
      final InvocationContext invocationContext =
          await _buildInvocationContext();
      final GkeCodeExecutor executor = GkeCodeExecutor();

      final Map<String, Object?> manifest = executor.createJobManifest(
        jobName: 'job1',
        configMapName: 'cfg1',
        invocationContext: invocationContext,
      );

      expect(manifest['kind'], 'Job');
      final Map spec = manifest['spec'] as Map;
      final Map template = spec['template'] as Map;
      final Map podSpec = template['spec'] as Map;
      expect(podSpec['runtimeClassName'], 'gvisor');
      expect(podSpec['containers'], isA<List>());
    });

    test('agent engine sandbox validates resource names', () {
      expect(
        () => AgentEngineSandboxCodeExecutor(
          sandboxResourceName:
              'projects/p1/locations/us-central1/reasoningEngines/1/sandboxEnvironments/2',
        ),
        returnsNormally,
      );

      expect(
        () => AgentEngineSandboxCodeExecutor(sandboxResourceName: 'invalid'),
        throwsArgumentError,
      );
    });
  });
}
