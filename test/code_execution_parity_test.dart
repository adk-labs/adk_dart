import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

class _FakeContainerRuntimeClient implements ContainerRuntimeClient {
  final List<String> buildCalls = <String>[];
  int startCalls = 0;
  int stopCalls = 0;
  final List<List<String>> execCommands = <List<String>>[];
  bool available = true;

  @override
  Future<void> buildImage({
    required String dockerPath,
    required String imageTag,
  }) async {
    buildCalls.add('$dockerPath|$imageTag');
  }

  @override
  Future<String> startContainer({required String imageTag}) async {
    startCalls += 1;
    return 'container-$startCalls';
  }

  @override
  Future<DockerExecResult> exec({
    required String containerId,
    required List<String> command,
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    execCommands.add(command);
    if (command.length == 2 &&
        command[0] == 'which' &&
        command[1] == 'python3') {
      return DockerExecResult(exitCode: 0, stdout: '/usr/bin/python3\n');
    }
    return DockerExecResult(exitCode: 0, stdout: 'ok', stderr: '');
  }

  @override
  Future<void> stopContainer({required String containerId}) async {
    stopCalls += 1;
  }

  @override
  Future<bool> isAvailable() async => available;
}

class _RecordedDockerProcessRunner {
  final List<List<String>> argumentHistory = <List<String>>[];
  final List<ProcessResult> queuedResults = <ProcessResult>[];

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    argumentHistory.add(List<String>.from(arguments));
    if (queuedResults.isNotEmpty) {
      return queuedResults.removeAt(0);
    }
    return ProcessResult(0, 0, '', '');
  }
}

class _FakeAgentEngineSandboxClient implements AgentEngineSandboxClient {
  _FakeAgentEngineSandboxClient({
    this.jsonPayload = '{"stdout":"remote ok","stderr":"remote warn"}',
  });

  int createSandboxCalls = 0;
  String? lastAgentEngineResourceName;
  String? lastSandboxResourceName;
  Map<String, Object?>? lastInputData;
  final String jsonPayload;

  @override
  Future<String> createSandbox({
    required String agentEngineResourceName,
  }) async {
    createSandboxCalls += 1;
    lastAgentEngineResourceName = agentEngineResourceName;
    return '$agentEngineResourceName/sandboxEnvironments/99';
  }

  @override
  Future<AgentEngineSandboxExecutionResponse> executeCode({
    required String sandboxResourceName,
    required Map<String, Object?> inputData,
  }) async {
    lastSandboxResourceName = sandboxResourceName;
    lastInputData = inputData;
    return AgentEngineSandboxExecutionResponse(
      outputs: <AgentEngineSandboxOutput>[
        AgentEngineSandboxOutput(
          mimeType: 'application/json',
          data: utf8.encode(jsonPayload),
        ),
        AgentEngineSandboxOutput(
          mimeType: 'image/png',
          data: <int>[1, 2, 3],
          metadata: <String, Object?>{
            'attributes': <String, Object?>{'file_name': 'plot.png'},
          },
        ),
      ],
    );
  }
}

class _FakeVertexClient implements VertexCodeInterpreterClient {
  String? lastCode;
  List<CodeExecutionFile>? lastInputFiles;
  String? lastSessionId;

  @override
  Future<Map<String, Object?>> execute({
    required String code,
    List<CodeExecutionFile>? inputFiles,
    String? sessionId,
  }) async {
    lastCode = code;
    lastInputFiles = inputFiles;
    lastSessionId = sessionId;
    return <String, Object?>{
      'execution_result': 'vertex ok',
      'execution_error': '',
      'output_files': <Object?>[
        <String, Object?>{'name': 'data.csv', 'contents': 'a,b\n1,2'},
        <String, Object?>{
          'name': 'plot.png',
          'contents': <int>[3, 4, 5],
        },
      ],
    };
  }
}

class _FakeGkeApiClient implements GkeApiClient {
  _FakeGkeApiClient({
    this.watchResult,
    this.failPatchConfigMap = false,
    this.watchError,
  });

  final GkeJobWatchResult? watchResult;
  final bool failPatchConfigMap;
  final Object? watchError;
  Map<String, Object?>? createdConfigMap;
  Map<String, Object?>? createdJob;
  Map<String, Object?>? patchedConfigMap;
  String? patchedConfigMapName;

  @override
  Future<void> createCodeConfigMap({
    required String namespace,
    required Map<String, Object?> body,
  }) async {
    createdConfigMap = <String, Object?>{'namespace': namespace, 'body': body};
  }

  @override
  Future<Map<String, Object?>> createJob({
    required String namespace,
    required Map<String, Object?> body,
  }) async {
    createdJob = <String, Object?>{'namespace': namespace, 'body': body};
    return <String, Object?>{
      'apiVersion': 'batch/v1',
      'kind': 'Job',
      'metadata': <String, Object?>{'name': 'adk-exec-123', 'uid': 'uid-123'},
    };
  }

  @override
  Future<void> patchConfigMap({
    required String namespace,
    required String name,
    required Map<String, Object?> body,
  }) async {
    if (failPatchConfigMap) {
      throw StateError('patch failed');
    }
    patchedConfigMapName = name;
    patchedConfigMap = <String, Object?>{
      'namespace': namespace,
      'name': name,
      'body': body,
    };
  }

  @override
  Future<GkeJobWatchResult> watchJob({
    required String namespace,
    required String jobName,
    required int timeoutSeconds,
  }) async {
    final Object? error = watchError;
    if (error != null) {
      throw error;
    }
    return watchResult ?? GkeJobWatchResult(status: GkeJobStatus.succeeded);
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

    test('process runtime forwards host to docker subcommands', () async {
      final _RecordedDockerProcessRunner runner = _RecordedDockerProcessRunner()
        ..queuedResults.addAll(<ProcessResult>[
          ProcessResult(0, 0, 'Docker version 26', ''), // --version
          ProcessResult(0, 0, '', ''), // build
          ProcessResult(0, 0, 'container-id\n', ''), // run
          ProcessResult(0, 0, 'ok', ''), // exec
          ProcessResult(0, 0, '', ''), // stop
        ]);
      final ProcessContainerRuntimeClient runtime =
          ProcessContainerRuntimeClient(
            host: 'tcp://127.0.0.1:2375',
            processRunner: runner.run,
          );

      expect(await runtime.isAvailable(), isTrue);
      await runtime.buildImage(
        dockerPath: '/tmp/docker',
        imageTag: 'img:latest',
      );
      final String containerId = await runtime.startContainer(
        imageTag: 'img:latest',
      );
      expect(containerId, 'container-id');
      await runtime.exec(
        containerId: containerId,
        command: const <String>['python3', '--version'],
      );
      await runtime.stopContainer(containerId: containerId);

      expect(runner.argumentHistory[0], const <String>[
        '-H',
        'tcp://127.0.0.1:2375',
        '--version',
      ]);
      expect(runner.argumentHistory[1], const <String>[
        '-H',
        'tcp://127.0.0.1:2375',
        'build',
        '-t',
        'img:latest',
        '/tmp/docker',
      ]);
      expect(runner.argumentHistory[2].sublist(0, 6), const <String>[
        '-H',
        'tcp://127.0.0.1:2375',
        'run',
        '-d',
        '--rm',
        '-t',
      ]);
      expect(runner.argumentHistory[3].sublist(0, 3), const <String>[
        '-H',
        'tcp://127.0.0.1:2375',
        'exec',
      ]);
      expect(runner.argumentHistory[4], const <String>[
        '-H',
        'tcp://127.0.0.1:2375',
        'stop',
        'container-id',
      ]);
    });

    test('container executor fails fast on invalid dockerPath', () async {
      final _FakeContainerRuntimeClient runtime = _FakeContainerRuntimeClient();
      final String missingPath =
          '${Directory.systemTemp.path}/adk_docker_missing_${DateTime.now().microsecondsSinceEpoch}';
      final ContainerCodeExecutor executor = ContainerCodeExecutor(
        image: 'img:latest',
        dockerPath: missingPath,
        runtimeClient: runtime,
      );

      final CodeExecutionResult result = await executor.execute(
        CodeExecutionRequest(command: 'print(1)'),
      );

      expect(result.exitCode, -1);
      expect(result.stderr, contains('Invalid Docker path'));
      expect(runtime.startCalls, 0);
    });

    test('container executor reuses initialized container runtime', () async {
      final _FakeContainerRuntimeClient runtime = _FakeContainerRuntimeClient();
      final ContainerCodeExecutor executor = ContainerCodeExecutor(
        image: 'custom-image:latest',
        runtimeClient: runtime,
      );

      final CodeExecutionResult first = await executor.execute(
        CodeExecutionRequest(command: 'print(1)'),
      );
      final CodeExecutionResult second = await executor.execute(
        CodeExecutionRequest(command: 'print(2)'),
      );

      expect(first.stdout, 'ok');
      expect(second.stdout, 'ok');
      expect(runtime.startCalls, 1);
      expect(
        runtime.execCommands.where(
          (List<String> cmd) => cmd.first == 'python3',
        ),
        hasLength(2),
      );

      await executor.closeContainer();
      expect(runtime.stopCalls, 1);
    });

    test('container executor rejects unsafe input file paths', () async {
      final InvocationContext invocationContext =
          await _buildInvocationContext();
      final _FakeContainerRuntimeClient runtime = _FakeContainerRuntimeClient();
      final ContainerCodeExecutor executor = ContainerCodeExecutor(
        image: 'custom-image:latest',
        runtimeClient: runtime,
      );

      final CodeExecutionResult parentTraversal = await executor.executeCode(
        invocationContext,
        CodeExecutionInput(
          code: 'print(1)',
          inputFiles: <CodeExecutionFile>[
            CodeExecutionFile(name: '../escape.txt', content: 'bad'),
          ],
        ),
      );
      expect(parentTraversal.exitCode, -1);
      expect(parentTraversal.stderr, contains('Invalid input file name'));

      final CodeExecutionResult absolute = await executor.executeCode(
        invocationContext,
        CodeExecutionInput(
          code: 'print(1)',
          inputFiles: <CodeExecutionFile>[
            CodeExecutionFile(name: '/tmp/escape.txt', content: 'bad'),
          ],
        ),
      );
      expect(absolute.exitCode, -1);
      expect(absolute.stderr, contains('Invalid input file name'));

      final CodeExecutionResult drivePrefixed = await executor.executeCode(
        invocationContext,
        CodeExecutionInput(
          code: 'print(1)',
          inputFiles: <CodeExecutionFile>[
            CodeExecutionFile(name: r'C:\temp\escape.txt', content: 'bad'),
          ],
        ),
      );
      expect(drivePrefixed.exitCode, -1);
      expect(drivePrefixed.stderr, contains('Invalid input file name'));
      expect(runtime.startCalls, 0);
    });

    test(
      'container executor accepts nested relative input file paths',
      () async {
        final InvocationContext invocationContext =
            await _buildInvocationContext();
        final _FakeContainerRuntimeClient runtime =
            _FakeContainerRuntimeClient();
        final ContainerCodeExecutor executor = ContainerCodeExecutor(
          image: 'custom-image:latest',
          runtimeClient: runtime,
        );

        final CodeExecutionResult result = await executor.executeCode(
          invocationContext,
          CodeExecutionInput(
            code: 'print(1)',
            inputFiles: <CodeExecutionFile>[
              CodeExecutionFile(name: 'dir/input.txt', content: 'safe'),
            ],
          ),
        );

        expect(result.exitCode, 0);
        expect(result.stdout, 'ok');
        expect(runtime.startCalls, 1);
        expect(
          runtime.execCommands.where(
            (List<String> command) =>
                command.length == 3 && command.first == 'python3',
          ),
          hasLength(1),
        );
      },
    );

    test('container executor builds image when dockerPath is set', () async {
      final _FakeContainerRuntimeClient runtime = _FakeContainerRuntimeClient();
      final Directory dockerDir = await Directory.systemTemp.createTemp(
        'adk_docker_dir_',
      );
      final ContainerCodeExecutor executor = ContainerCodeExecutor(
        image: 'built:latest',
        dockerPath: dockerDir.path,
        runtimeClient: runtime,
      );

      try {
        await executor.execute(CodeExecutionRequest(command: 'print(3)'));

        expect(runtime.buildCalls, hasLength(1));
        expect(runtime.buildCalls.first, '${dockerDir.path}|built:latest');
        await executor.closeContainer();
      } finally {
        await dockerDir.delete(recursive: true);
      }
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

    test('gke executor uses api client orchestration path', () async {
      final InvocationContext invocationContext =
          await _buildInvocationContext();
      final _FakeGkeApiClient apiClient = _FakeGkeApiClient(
        watchResult: GkeJobWatchResult(
          status: GkeJobStatus.succeeded,
          logs: 'job logs',
        ),
      );
      final GkeCodeExecutor executor = GkeCodeExecutor(apiClient: apiClient);

      final CodeExecutionResult result = await executor.executeCode(
        invocationContext,
        CodeExecutionInput(code: 'print(42)'),
      );

      expect(result.stdout, 'job logs');
      expect(apiClient.createdConfigMap, isNotNull);
      expect(apiClient.createdJob, isNotNull);
      expect(apiClient.patchedConfigMapName, isNotNull);
    });

    test('gke executor maps failed and timeout watch statuses', () async {
      final InvocationContext invocationContext =
          await _buildInvocationContext();

      final GkeCodeExecutor failedExecutor = GkeCodeExecutor(
        apiClient: _FakeGkeApiClient(
          watchResult: GkeJobWatchResult(
            status: GkeJobStatus.failed,
            logs: 'failure logs',
          ),
        ),
      );
      final CodeExecutionResult failed = await failedExecutor.executeCode(
        invocationContext,
        CodeExecutionInput(code: 'raise RuntimeError()'),
      );
      expect(failed.stderr, contains('Job failed. Logs:'));

      final GkeCodeExecutor timeoutExecutor = GkeCodeExecutor(
        apiClient: _FakeGkeApiClient(
          watchResult: GkeJobWatchResult(
            status: GkeJobStatus.timedOut,
            errorMessage: 'timeout reached',
          ),
        ),
      );
      final CodeExecutionResult timedOut = await timeoutExecutor.executeCode(
        invocationContext,
        CodeExecutionInput(code: 'while True: pass'),
      );
      expect(timedOut.timedOut, isTrue);
      expect(timedOut.stderr, contains('timeout reached'));
    });

    test('gke executor ignores owner-reference patch failure', () async {
      final InvocationContext invocationContext =
          await _buildInvocationContext();
      final _FakeGkeApiClient apiClient = _FakeGkeApiClient(
        watchResult: GkeJobWatchResult(
          status: GkeJobStatus.succeeded,
          logs: 'ok',
        ),
        failPatchConfigMap: true,
      );
      final GkeCodeExecutor executor = GkeCodeExecutor(apiClient: apiClient);

      final CodeExecutionResult result = await executor.executeCode(
        invocationContext,
        CodeExecutionInput(code: 'print(42)'),
      );

      expect(result.stdout, 'ok');
      expect(result.stderr, isEmpty);
      expect(apiClient.createdJob, isNotNull);
    });

    test(
      'gke executor maps watch timeout exceptions to timedOut result',
      () async {
        final InvocationContext invocationContext =
            await _buildInvocationContext();
        final GkeCodeExecutor executor = GkeCodeExecutor(
          apiClient: _FakeGkeApiClient(
            watchError: TimeoutException('watch timed out'),
          ),
        );

        final CodeExecutionResult result = await executor.executeCode(
          invocationContext,
          CodeExecutionInput(code: 'print(42)'),
        );

        expect(result.exitCode, -1);
        expect(result.timedOut, isTrue);
        expect(result.stderr, contains('Executor timed out'));
      },
    );

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

    test(
      'agent engine sandbox executor uses remote client when configured',
      () async {
        final InvocationContext invocationContext =
            await _buildInvocationContext();
        final _FakeAgentEngineSandboxClient client =
            _FakeAgentEngineSandboxClient();
        final AgentEngineSandboxCodeExecutor executor =
            AgentEngineSandboxCodeExecutor(
              agentEngineResourceName:
                  'projects/p1/locations/us-central1/reasoningEngines/77',
              sandboxClient: client,
            );

        final CodeExecutionResult result = await executor.executeCode(
          invocationContext,
          CodeExecutionInput(
            code: 'print("remote")',
            inputFiles: <CodeExecutionFile>[
              CodeExecutionFile(name: 'input.txt', content: 'hello'),
            ],
          ),
        );

        expect(client.createSandboxCalls, 1);
        expect(result.stdout, 'remote ok');
        expect(result.stderr, 'remote warn');
        expect(result.outputFiles, hasLength(1));
        expect(result.outputFiles.first.name, 'plot.png');
        expect(result.outputFiles.first.mimeType, 'image/png');
      },
    );

    test(
      'agent engine sandbox executor prefers msg_out/msg_err in json payload',
      () async {
        final InvocationContext invocationContext =
            await _buildInvocationContext();
        final _FakeAgentEngineSandboxClient
        client = _FakeAgentEngineSandboxClient(
          jsonPayload:
              '{"msg_out":"remote msg","msg_err":"remote issue","stdout":"legacy out","stderr":"legacy err"}',
        );
        final AgentEngineSandboxCodeExecutor executor =
            AgentEngineSandboxCodeExecutor(
              agentEngineResourceName:
                  'projects/p1/locations/us-central1/reasoningEngines/77',
              sandboxClient: client,
            );

        final CodeExecutionResult result = await executor.executeCode(
          invocationContext,
          CodeExecutionInput(code: 'print("remote")'),
        );

        expect(result.stdout, 'remote msg');
        expect(result.stderr, 'remote issue');
      },
    );

    test(
      'vertex executor parses extension response and preserves imports',
      () async {
        final InvocationContext invocationContext =
            await _buildInvocationContext();
        final _FakeVertexClient client = _FakeVertexClient();
        final VertexAiCodeExecutor executor = VertexAiCodeExecutor(
          client: client,
        );

        final CodeExecutionResult result = await executor.executeCode(
          invocationContext,
          CodeExecutionInput(
            code: 'print("vertex")',
            inputFiles: <CodeExecutionFile>[
              CodeExecutionFile(name: 'seed.csv', content: 'x,y\\n1,2'),
            ],
            executionId: 'session_123',
          ),
        );

        expect(client.lastCode, contains('import pandas as pd'));
        expect(client.lastCode, contains('print("vertex")'));
        expect(client.lastSessionId, 'session_123');
        expect(client.lastInputFiles, hasLength(1));

        expect(result.stdout, 'vertex ok');
        expect(result.stderr, isEmpty);
        expect(result.outputFiles, hasLength(2));
        expect(result.outputFiles[0].mimeType, 'text/csv');
        expect(result.outputFiles[1].mimeType, 'image/png');
      },
    );
  });
}
