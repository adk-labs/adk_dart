import 'dart:convert';
import 'dart:typed_data';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FakeOpenSandboxClient implements OpenSandboxClient {
  final Map<String, Uint8List> files = <String, Uint8List>{};
  final List<String> commands = <String>[];

  @override
  Future<String> createOrAttachSandbox({
    required String image,
    Duration? timeout,
    Map<String, String>? envVars,
  }) async => 'sbx-fake-123';

  @override
  Future<EnvironmentExecutionResult> execute({
    required String sandboxId,
    required String command,
    String? workingDir,
    Duration? timeout,
    Map<String, String>? envVars,
  }) async {
    commands.add(command);
    return EnvironmentExecutionResult(exitCode: 0, stdout: 'ok', stderr: '');
  }

  @override
  Future<Uint8List> readFile({
    required String sandboxId,
    required String path,
  }) async {
    final data = files[path];
    if (data == null) {
      throw StateError('File not found: $path');
    }
    return data;
  }

  @override
  Future<void> writeFile({
    required String sandboxId,
    required String path,
    required List<int> bytes,
  }) async {
    files[path] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> closeSandbox(String sandboxId) async {}
}

void main() {
  group('OpenSandboxEnvironment', () {
    test('initializes and executes operations with OpenSandboxClient', () async {
      final fakeClient = _FakeOpenSandboxClient();
      final env = OpenSandboxEnvironment(
        sandboxId: 'sbx-123',
        client: fakeClient,
      );

      await env.initialize();
      expect(env.isInitialized, isTrue);
      expect(env.sandboxId, equals('sbx-123'));

      await env.writeFile('hello.txt', 'Hello World');
      final content = await env.readFile('hello.txt');
      expect(utf8.decode(content), equals('Hello World'));

      await env.close();
    });
  });

  group('AgentEngineEnvironment', () {
    test('initializes and executes with ShellBackedAgentEngineSandboxClient', () async {
      final executedCommands = <String>[];
      final client = ShellBackedAgentEngineSandboxClient(
        commandRunner: ({
          required String sandboxResourceName,
          required String command,
          String? workingDir,
          Duration? timeout,
          Map<String, String>? envVars,
        }) async {
          executedCommands.add(command);
          if (command.startsWith('base64 <')) {
            return EnvironmentExecutionResult(
              exitCode: 0,
              stdout: base64Encode(utf8.encode('sandbox file contents')),
              stderr: '',
            );
          }
          return EnvironmentExecutionResult(
            exitCode: 0,
            stdout: 'command output',
            stderr: '',
          );
        },
      );

      final env = AgentEngineEnvironment(
        agentEngineResourceName: 'projects/p/locations/l/reasoningEngines/1',
        client: client,
      );

      await env.initialize();
      expect(env.isInitialized, isTrue);

      final result = await env.execute('echo hi');
      expect(result.exitCode, equals(0));
      expect(result.stdout, equals('command output'));
      expect(executedCommands.first, contains('echo hi'));

      final fileData = await env.readFile('test.txt');
      expect(utf8.decode(fileData), equals('sandbox file contents'));

      await env.close();
    });
  });
}
