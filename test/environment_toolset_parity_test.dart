import 'dart:convert';
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
        expect(
          request.config.systemInstruction,
          startsWith('Your environment is at '),
        );
        await toolset.close();
      },
    );

    test('public environment tools can be constructed directly', () async {
      final Directory workspace = await Directory.systemTemp.createTemp(
        'environment_public_tools_',
      );
      addTearDown(() => workspace.delete(recursive: true));

      final LocalEnvironment environment = LocalEnvironment(
        workingDirectory: workspace,
      );
      final Context context = _toolContext();
      final List<BaseTool> tools = <BaseTool>[
        ExecuteTool(environment),
        ReadFileTool(environment, maxOutputChars: 100),
        EditFileTool(environment),
        WriteFileTool(environment),
      ];

      expect(tools.map((BaseTool tool) => tool.name), <String>[
        'Execute',
        'ReadFile',
        'EditFile',
        'WriteFile',
      ]);
      expect(tools[0].getDeclaration()!.name, 'Execute');
      expect(tools[1].getDeclaration()!.name, 'ReadFile');
      expect(tools[2].getDeclaration()!.name, 'EditFile');
      expect(tools[3].getDeclaration()!.name, 'WriteFile');

      final Object? writeResult = await tools[3].run(
        args: <String, dynamic>{'path': 'public.txt', 'content': 'old\n'},
        toolContext: context,
      );
      expect((writeResult! as Map<String, Object?>)['status'], 'ok');

      final Object? editResult = await tools[2].run(
        args: <String, dynamic>{
          'path': 'public.txt',
          'old_string': 'old',
          'new_string': 'new',
        },
        toolContext: context,
      );
      expect((editResult! as Map<String, Object?>)['status'], 'ok');

      final Object? readResult = await tools[1].run(
        args: <String, dynamic>{'path': 'public.txt'},
        toolContext: context,
      );
      expect((readResult! as Map<String, Object?>)['content'], contains('new'));

      final Object? executeResult = await tools[0].run(
        args: <String, dynamic>{'command': 'printf direct'},
        toolContext: context,
      );
      expect((executeResult! as Map<String, Object?>)['stdout'], 'direct');
    });

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

    test(
      'EditFile matches CRLF files and escapes regex metacharacters',
      () async {
        final Directory workspace = await Directory.systemTemp.createTemp(
          'environment_toolset_edit_crlf_',
        );
        addTearDown(() => workspace.delete(recursive: true));

        final EnvironmentToolset toolset = EnvironmentToolset(
          environment: LocalEnvironment(workingDirectory: workspace),
        );
        final Map<String, BaseTool> tools = await _resolveTools(toolset);
        final Context context = _toolContext();

        await tools['WriteFile']!.run(
          args: <String, dynamic>{
            'path': 'regex.txt',
            'content': 'before\r\na+b. [x]\r\nafter\r\n',
          },
          toolContext: context,
        );

        final Object? editResult = await tools['EditFile']!.run(
          args: <String, dynamic>{
            'path': 'regex.txt',
            'old_string': 'a+b. [x]\nafter',
            'new_string': r'a+b. [ok] $literal',
          },
          toolContext: context,
        );

        expect((editResult! as Map<String, Object?>)['status'], 'ok');
        expect(
          await File(
            '${workspace.path}${Platform.pathSeparator}regex.txt',
          ).readAsString(),
          'before\r\na+b. [ok] \$literal\r\n',
        );

        await toolset.close();
      },
    );

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

    test('LocalEnvironment accepts path-like Uri and File inputs', () async {
      final Directory workspace = await Directory.systemTemp.createTemp(
        'environment_toolset_pathlike_',
      );
      addTearDown(() => workspace.delete(recursive: true));

      final LocalEnvironment environment = LocalEnvironment(
        workingDirectory: workspace,
      );
      final Uri nestedFile = Uri.file(
        '${workspace.path}${Platform.pathSeparator}nested${Platform.pathSeparator}hello.txt',
      );

      await environment.writeFile(nestedFile, 'hello');
      final List<int> bytes = await environment.readFile(
        File.fromUri(nestedFile),
      );

      expect(utf8.decode(bytes), 'hello');
    });

    test('applies custom maxOutputChars to command and file output', () async {
      final Directory workspace = await Directory.systemTemp.createTemp(
        'environment_toolset_truncate_',
      );
      addTearDown(() => workspace.delete(recursive: true));

      final EnvironmentToolset toolset = EnvironmentToolset(
        environment: LocalEnvironment(workingDirectory: workspace),
        maxOutputChars: 5,
      );
      final Map<String, BaseTool> tools = await _resolveTools(toolset);
      final Context context = _toolContext();

      final Object? executeResult = await tools['Execute']!.run(
        args: <String, dynamic>{'command': 'printf 1234567890'},
        toolContext: context,
      );
      final Map<String, Object?> executePayload =
          executeResult! as Map<String, Object?>;
      expect(executePayload['stdout'], startsWith('12345\n... (truncated'));

      await tools['WriteFile']!.run(
        args: <String, dynamic>{'path': 'long.txt', 'content': 'abcdefghij\n'},
        toolContext: context,
      );
      final Object? readResult = await tools['ReadFile']!.run(
        args: <String, dynamic>{'path': 'long.txt'},
        toolContext: context,
      );
      final Map<String, Object?> readPayload =
          readResult! as Map<String, Object?>;
      expect(readPayload['content'], startsWith('     \n... (truncated'));

      await toolset.close();
    });
  });
}
