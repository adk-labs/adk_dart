import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Context _toolContext() {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_environment_toolset',
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(id: 'session', appName: 'app', userId: 'user'),
  );
  return Context(invocationContext);
}

Future<Map<String, BaseTool>> _resolveTools(EnvironmentToolset toolset) async {
  final List<BaseTool> tools = await toolset.getTools();
  return <String, BaseTool>{for (final BaseTool tool in tools) tool.name: tool};
}

void main() {
  group('EnvironmentToolset parity', () {
    test(
      'injects environment instruction and exposes expected tools',
      () async {
        final Directory workspace = await Directory.systemTemp.createTemp(
          'environment_toolset_',
        );
        addTearDown(() => workspace.delete(recursive: true));

        final EnvironmentToolset toolset = EnvironmentToolset(
          environment: LocalEnvironment(workingDirectory: workspace),
        );
        final LlmRequest request = LlmRequest(model: 'test-model');

        await toolset.processLlmRequest(
          toolContext: _toolContext(),
          llmRequest: request,
        );
        final Map<String, BaseTool> tools = await _resolveTools(toolset);

        expect(tools.keys, <String>[
          'Execute',
          'ReadFile',
          'EditFile',
          'WriteFile',
        ]);
        expect(request.config.systemInstruction, contains(workspace.path));
        await toolset.close();
      },
    );

    test('writes, reads, edits, and executes within the workspace', () async {
      final Directory workspace = await Directory.systemTemp.createTemp(
        'environment_toolset_io_',
      );
      addTearDown(() => workspace.delete(recursive: true));

      final EnvironmentToolset toolset = EnvironmentToolset(
        environment: LocalEnvironment(workingDirectory: workspace),
      );
      final Map<String, BaseTool> tools = await _resolveTools(toolset);
      final Context context = _toolContext();

      final Object? writeResult = await tools['WriteFile']!.run(
        args: <String, dynamic>{
          'path': 'hello.txt',
          'content': 'one\ntwo\nthree\n',
        },
        toolContext: context,
      );
      expect((writeResult! as Map<String, Object?>)['status'], 'ok');

      final Object? readResult = await tools['ReadFile']!.run(
        args: <String, dynamic>{
          'path': 'hello.txt',
          'start_line': 2,
          'end_line': 3,
        },
        toolContext: context,
      );
      final Map<String, Object?> readPayload =
          readResult! as Map<String, Object?>;
      expect(readPayload['content'], contains('     2\ttwo'));
      expect(readPayload['content'], contains('     3\tthree'));

      final Object? editResult = await tools['EditFile']!.run(
        args: <String, dynamic>{
          'path': 'hello.txt',
          'old_string': 'two',
          'new_string': 'updated',
        },
        toolContext: context,
      );
      expect((editResult! as Map<String, Object?>)['status'], 'ok');
      expect(
        await File(
          '${workspace.path}${Platform.pathSeparator}hello.txt',
        ).readAsString(),
        'one\nupdated\nthree\n',
      );

      final Object? executeResult = await tools['Execute']!.run(
        args: <String, dynamic>{'command': 'pwd'},
        toolContext: context,
      );
      final Map<String, Object?> executePayload =
          executeResult! as Map<String, Object?>;
      expect(executePayload['status'], 'ok');
      expect(
        '${executePayload['stdout']}'.trim(),
        Directory(workspace.path).resolveSymbolicLinksSync(),
      );

      await toolset.close();
    });

    test('rejects file access outside the workspace', () async {
      final Directory workspace = await Directory.systemTemp.createTemp(
        'environment_toolset_guard_',
      );
      addTearDown(() => workspace.delete(recursive: true));

      final EnvironmentToolset toolset = EnvironmentToolset(
        environment: LocalEnvironment(workingDirectory: workspace),
      );
      final Map<String, BaseTool> tools = await _resolveTools(toolset);
      final Context context = _toolContext();

      final Object? writeResult = await tools['WriteFile']!.run(
        args: <String, dynamic>{'path': '../escape.txt', 'content': 'blocked'},
        toolContext: context,
      );
      final Object? readResult = await tools['ReadFile']!.run(
        args: <String, dynamic>{'path': '../escape.txt'},
        toolContext: context,
      );

      expect(
        (writeResult! as Map<String, Object?>)['error'],
        contains('outside the working directory'),
      );
      expect(
        (readResult! as Map<String, Object?>)['error'],
        contains('outside the working directory'),
      );
      await toolset.close();
    });
  });
}
