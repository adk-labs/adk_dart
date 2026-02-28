import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('bash tool parity', () {
    test('validates command prefix policy', () async {
      final ExecuteBashTool tool = ExecuteBashTool(
        policy: BashToolPolicy(allowedCommandPrefixes: <String>['ls ']),
      );

      final Object? result = await tool.run(
        args: <String, dynamic>{'command': 'echo hello'},
        toolContext: _toolContext(confirmed: true),
      );

      expect(result, isA<Map<String, Object?>>());
      expect(
        (result! as Map<String, Object?>)['error'],
        contains('Command blocked.'),
      );
    });

    test('requests confirmation before execution', () async {
      final ExecuteBashTool tool = ExecuteBashTool();
      final Context context = _toolContext();

      final Object? result = await tool.run(
        args: <String, dynamic>{'command': 'echo hello'},
        toolContext: context,
      );

      expect(
        (result as Map<String, Object?>)['error'],
        contains('requires confirmation'),
      );
      expect(
        context.actions.requestedToolConfirmations.containsKey('fc1'),
        isTrue,
      );
      expect(context.actions.skipSummarization, isTrue);
    });

    test('rejects execution when confirmation is denied', () async {
      final ExecuteBashTool tool = ExecuteBashTool();

      final Object? result = await tool.run(
        args: <String, dynamic>{'command': 'echo hello'},
        toolContext: _toolContext(confirmed: false),
      );

      expect((result as Map<String, Object?>)['error'], contains('rejected'));
    });

    test('executes confirmed command in workspace directory', () async {
      final Directory workspace = await Directory.systemTemp.createTemp(
        'bash_tool_test_',
      );
      addTearDown(() => workspace.delete(recursive: true));

      final ExecuteBashTool tool = ExecuteBashTool(workspace: workspace);
      final Object? result = await tool.run(
        args: <String, dynamic>{
          'command': 'printf hello > output.txt && cat output.txt',
        },
        toolContext: _toolContext(confirmed: true),
      );

      final Map<String, Object?> payload = result! as Map<String, Object?>;
      expect(payload['returncode'], 0);
      expect('${payload['stdout']}', 'hello');
      expect(File('${workspace.path}/output.txt').existsSync(), isTrue);
    });
  });
}

Context _toolContext({bool? confirmed}) {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv-bash',
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(id: 'session', appName: 'app', userId: 'user'),
  );
  return Context(
    invocationContext,
    functionCallId: 'fc1',
    toolConfirmation: confirmed == null
        ? null
        : ToolConfirmation(confirmed: confirmed),
  );
}
