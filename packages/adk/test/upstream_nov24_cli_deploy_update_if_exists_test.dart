import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adk/cli.dart' as cli;
import 'package:adk/src/cli/cli_deploy.dart';
import 'package:test/test.dart';

class _CapturedSink {
  _CapturedSink() : _controller = StreamController<List<int>>() {
    _controller.stream.listen(_bytes.addAll);
    sink = IOSink(_controller.sink);
  }

  final StreamController<List<int>> _controller;
  final List<int> _bytes = <int>[];
  late final IOSink sink;

  Future<String> closeAndRead() async {
    await sink.flush();
    await sink.close();
    await _controller.done;
    return utf8.decode(_bytes);
  }
}

class _FakeRuntimesClient implements AgentEngineRuntimesClient {
  _FakeRuntimesClient({
    this.existing = const <AgentEngineRuntimeInfo>[],
    this.listError,
    this.updateError,
  });

  static const String _createdName =
      'projects/p/locations/l/reasoningEngines/newly-created';

  final List<AgentEngineRuntimeInfo> existing;
  final Object? listError;
  final Object? updateError;

  final List<String?> listFilters = <String?>[];
  int createCount = 0;
  final List<(String, Map<String, Object?>)> updates =
      <(String, Map<String, Object?>)>[];
  final List<String> deletes = <String>[];

  @override
  Future<List<AgentEngineRuntimeInfo>> list({String? filter}) async {
    listFilters.add(filter);
    if (listError != null) {
      throw listError!;
    }
    return List<AgentEngineRuntimeInfo>.of(existing);
  }

  @override
  Future<AgentEngineRuntimeInfo> create() async {
    createCount += 1;
    return const AgentEngineRuntimeInfo(
      name: _createdName,
      updateTime: '2026-11-09T00:00:00Z',
    );
  }

  @override
  Future<void> update({
    required String name,
    required Map<String, Object?> config,
  }) async {
    updates.add((name, Map<String, Object?>.of(config)));
    if (updateError != null) {
      throw updateError!;
    }
  }

  @override
  Future<void> delete({required String name}) async {
    deletes.add(name);
  }
}

void main() {
  group('upstream 84cb0742b - Agent Engine duplicate warning and --update_if_exists', () {
    late Directory tempRoot;
    late Directory agentDir;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('adk_ae_update_test_');
      agentDir = Directory('${tempRoot.path}${Platform.pathSeparator}my_agent')
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('no existing match creates without warning and escapes filter quotes', () async {
      final _FakeRuntimesClient client = _FakeRuntimesClient(existing: const []);
      final _CapturedSink out = _CapturedSink();
      final _CapturedSink err = _CapturedSink();

      final String resourceName = await deployToAgentEngine(
        client: client,
        agentFolder: agentDir.path,
        project: 'my-gcp-project',
        region: 'us-central1',
        displayName: 'My "Quoted" Agent',
        out: out.sink,
        err: err.sink,
      );

      final String stdoutText = await out.closeAndRead();
      final String stderrText = await err.closeAndRead();

      expect(client.listFilters, <String?>[
        r'display_name="My \"Quoted\" Agent"',
      ]);
      expect(client.createCount, 1);
      expect(client.updates, hasLength(1));
      expect(
        client.updates.first.$1,
        'projects/p/locations/l/reasoningEngines/newly-created',
      );
      expect(
        resourceName,
        'projects/p/locations/l/reasoningEngines/newly-created',
      );
      expect(stdoutText, contains('Created a new instance:'));
      expect(stderrText, isNot(contains('WARNING:')));
    });

    test('warns to stderr when duplicate display name exists and still creates', () async {
      const String existingName =
          'projects/my-gcp-project/locations/us-central1/reasoningEngines/111';
      final _FakeRuntimesClient client = _FakeRuntimesClient(
        existing: const <AgentEngineRuntimeInfo>[
          AgentEngineRuntimeInfo(
            name: existingName,
            updateTime: '2026-11-08T12:00:00Z',
          ),
        ],
      );
      final _CapturedSink out = _CapturedSink();
      final _CapturedSink err = _CapturedSink();

      await deployToAgentEngine(
        client: client,
        agentFolder: agentDir.path,
        project: 'my-gcp-project',
        region: 'us-central1',
        displayName: 'My Test Agent',
        out: out.sink,
        err: err.sink,
      );

      await out.closeAndRead();
      final String stderrText = await err.closeAndRead();

      expect(client.createCount, 1);
      expect(client.updates, hasLength(1));
      expect(
        client.updates.first.$1,
        'projects/p/locations/l/reasoningEngines/newly-created',
      );
      expect(stderrText, contains('WARNING: 1 Agent Runtime(s)'));
      expect(stderrText, contains(existingName));
      expect(stderrText, contains('2026-11-08T12:00:00Z'));
      expect(stderrText, contains('re-run with --agent_engine_id=<ID>'));
      expect(stderrText, isNot(contains('or --update_if_exists')));
      expect(
        stderrText,
        contains(
          '--update_if_exists only works once extra duplicates are deleted down to a single instance',
        ),
      );
    });

    test('formatAgentEngineRuntime falls back to ? when updateTime is missing', () {
      const AgentEngineRuntimeInfo runtime = AgentEngineRuntimeInfo(
        name: 'projects/p/locations/l/reasoningEngines/42',
      );
      expect(
        formatAgentEngineRuntime(runtime),
        '  projects/p/locations/l/reasoningEngines/42  (updated ?)',
      );
    });

    test('update_if_exists updates single match in place without create', () async {
      const String existingName =
          'projects/my-gcp-project/locations/us-central1/reasoningEngines/111';
      final _FakeRuntimesClient client = _FakeRuntimesClient(
        existing: const <AgentEngineRuntimeInfo>[
          AgentEngineRuntimeInfo(
            name: existingName,
            updateTime: '2026-11-09T00:00:00Z',
          ),
        ],
      );
      final _CapturedSink out = _CapturedSink();
      final _CapturedSink err = _CapturedSink();

      final String resourceName = await deployToAgentEngine(
        client: client,
        agentFolder: agentDir.path,
        project: 'my-gcp-project',
        region: 'us-central1',
        displayName: 'My Test Agent',
        updateIfExists: true,
        out: out.sink,
        err: err.sink,
      );

      final String stdoutText = await out.closeAndRead();
      final String stderrText = await err.closeAndRead();

      expect(resourceName, existingName);
      expect(client.createCount, 0);
      expect(client.updates, hasLength(1));
      expect(client.updates.first.$1, existingName);
      expect(
        stdoutText,
        contains('Updating existing instance with display name "My Test Agent": $existingName'),
      );
      expect(stderrText, isEmpty);
    });

    test('update_if_exists creates when no match exists', () async {
      final _FakeRuntimesClient client = _FakeRuntimesClient(existing: const []);
      final _CapturedSink out = _CapturedSink();
      final _CapturedSink err = _CapturedSink();

      final String resourceName = await deployToAgentEngine(
        client: client,
        agentFolder: agentDir.path,
        project: 'my-gcp-project',
        region: 'us-central1',
        displayName: 'My Test Agent',
        updateIfExists: true,
        out: out.sink,
        err: err.sink,
      );

      await out.closeAndRead();
      await err.closeAndRead();

      expect(client.createCount, 1);
      expect(client.updates, hasLength(1));
      expect(
        client.updates.first.$1,
        'projects/p/locations/l/reasoningEngines/newly-created',
      );
      expect(
        resourceName,
        'projects/p/locations/l/reasoningEngines/newly-created',
      );
    });

    test('update_if_exists fails on ambiguous matches listing candidates without creating', () async {
      const String first =
          'projects/my-gcp-project/locations/us-central1/reasoningEngines/111';
      const String second =
          'projects/my-gcp-project/locations/us-central1/reasoningEngines/222';
      final _FakeRuntimesClient client = _FakeRuntimesClient(
        existing: const <AgentEngineRuntimeInfo>[
          AgentEngineRuntimeInfo(
            name: first,
            updateTime: '2026-11-09T00:00:00Z',
          ),
          AgentEngineRuntimeInfo(
            name: second,
            updateTime: '2026-11-10T00:00:00Z',
          ),
        ],
      );
      bool prepared = false;

      await expectLater(
        () => deployToAgentEngine(
          client: client,
          agentFolder: agentDir.path,
          project: 'my-gcp-project',
          region: 'us-central1',
          displayName: 'My Test Agent',
          updateIfExists: true,
          onPrepareDeployment: (_, _) async {
            prepared = true;
          },
        ),
        throwsA(
          isA<AgentEngineDeployException>().having(
            (AgentEngineDeployException e) => e.message,
            'message',
            allOf(
              contains('2 Agent Runtimes'),
              contains(first),
              contains(second),
              contains('--agent_engine_id'),
              contains('replace --update_if_exists with --agent_engine_id'),
            ),
          ),
        ),
      );

      expect(client.createCount, 0);
      expect(client.updates, isEmpty);
      expect(prepared, isFalse);
    });

    test('update_if_exists fails in Express Mode before list, create, or prepare', () async {
      final _FakeRuntimesClient client = _FakeRuntimesClient();
      bool prepared = false;

      await expectLater(
        () => deployToAgentEngine(
          client: client,
          agentFolder: agentDir.path,
          project: null,
          region: null,
          displayName: 'My Test Agent',
          updateIfExists: true,
          onPrepareDeployment: (_, _) async {
            prepared = true;
          },
        ),
        throwsA(
          isA<AgentEngineDeployException>().having(
            (AgentEngineDeployException e) => e.message,
            'message',
            allOf(
              contains('Express Mode'),
              contains('replace --update_if_exists with --agent_engine_id'),
            ),
          ),
        ),
      );

      expect(client.listFilters, isEmpty);
      expect(client.createCount, 0);
      expect(client.updates, isEmpty);
      expect(prepared, isFalse);
    });

    test('update_if_exists fails when list raises instead of silently creating', () async {
      final _FakeRuntimesClient client = _FakeRuntimesClient(
        listError: StateError('IAM permission denied'),
      );
      bool prepared = false;

      await expectLater(
        () => deployToAgentEngine(
          client: client,
          agentFolder: agentDir.path,
          project: 'my-gcp-project',
          region: 'us-central1',
          displayName: 'My Test Agent',
          updateIfExists: true,
          onPrepareDeployment: (_, _) async {
            prepared = true;
          },
        ),
        throwsA(
          isA<AgentEngineDeployException>().having(
            (AgentEngineDeployException e) => e.message,
            'message',
            contains('IAM permission denied'),
          ),
        ),
      );

      expect(client.listFilters, hasLength(1));
      expect(client.createCount, 0);
      expect(client.updates, isEmpty);
      expect(prepared, isFalse);
    });

    test('findAgentEngineRuntimesByDisplayName handles empty display name', () async {
      final _FakeRuntimesClient client = _FakeRuntimesClient();

      expect(
        await findAgentEngineRuntimesByDisplayName(client, ''),
        isEmpty,
      );
      expect(
        await findAgentEngineRuntimesByDisplayName(client, null),
        isEmpty,
      );
      await expectLater(
        () => findAgentEngineRuntimesByDisplayName(
          client,
          '',
          raiseOnError: true,
        ),
        throwsA(
          isA<AgentEngineDeployException>().having(
            (AgentEngineDeployException e) => e.message,
            'message',
            contains('non-empty display name'),
          ),
        ),
      );
      expect(client.listFilters, isEmpty);
    });

    test('update_if_exists does not delete pre-existing runtime when update fails', () async {
      const String existingName =
          'projects/my-gcp-project/locations/us-central1/reasoningEngines/111';
      final _FakeRuntimesClient client = _FakeRuntimesClient(
        existing: const <AgentEngineRuntimeInfo>[
          AgentEngineRuntimeInfo(name: existingName),
        ],
        updateError: StateError('build failed'),
      );

      await expectLater(
        () => deployToAgentEngine(
          client: client,
          agentFolder: agentDir.path,
          project: 'my-gcp-project',
          region: 'us-central1',
          displayName: 'My Test Agent',
          updateIfExists: true,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('build failed'),
          ),
        ),
      );

      expect(client.createCount, 0);
      expect(client.deletes, isEmpty);
    });

    test('newly created runtime is deleted when update fails', () async {
      final _FakeRuntimesClient client = _FakeRuntimesClient(
        existing: const <AgentEngineRuntimeInfo>[],
        updateError: StateError('build failed'),
      );

      await expectLater(
        () => deployToAgentEngine(
          client: client,
          agentFolder: agentDir.path,
          project: 'my-gcp-project',
          region: 'us-central1',
          displayName: 'My Test Agent',
          updateIfExists: true,
        ),
        throwsA(isA<StateError>()),
      );

      expect(client.createCount, 1);
      expect(client.deletes, <String>[
        'projects/p/locations/l/reasoningEngines/newly-created',
      ]);
    });

    test('proceeds when duplicate check list raises without update_if_exists', () async {
      final _FakeRuntimesClient client = _FakeRuntimesClient(
        listError: StateError('IAM permission denied'),
      );

      await deployToAgentEngine(
        client: client,
        agentFolder: agentDir.path,
        project: 'my-gcp-project',
        region: 'us-central1',
        displayName: 'My Test Agent',
      );

      expect(client.listFilters, hasLength(1));
      expect(client.createCount, 1);
      expect(client.updates, hasLength(1));
    });

    test('uses display_name from .agent_engine_config.json for lookup', () async {
      File('${agentDir.path}${Platform.pathSeparator}.agent_engine_config.json')
          .writeAsStringSync(
            jsonEncode(<String, Object?>{'display_name': 'Config Display Name'}),
          );
      const String existingName =
          'projects/my-gcp-project/locations/us-central1/reasoningEngines/555';
      final _FakeRuntimesClient client = _FakeRuntimesClient(
        existing: const <AgentEngineRuntimeInfo>[
          AgentEngineRuntimeInfo(name: existingName),
        ],
      );

      final String resourceName = await deployToAgentEngine(
        client: client,
        agentFolder: agentDir.path,
        project: 'my-gcp-project',
        region: 'us-central1',
        updateIfExists: true,
      );

      expect(client.listFilters, <String?>[
        'display_name="Config Display Name"',
      ]);
      expect(resourceName, existingName);
      expect(client.createCount, 0);
    });

    test('CLI deploy agent_engine forwards --update_if_exists and rejects conflict with --agent_engine_id', () async {
      const String existingName =
          'projects/my-gcp-project/locations/us-central1/reasoningEngines/777';
      final _FakeRuntimesClient client = _FakeRuntimesClient(
        existing: const <AgentEngineRuntimeInfo>[
          AgentEngineRuntimeInfo(name: existingName),
        ],
      );

      final _CapturedSink okOut = _CapturedSink();
      final _CapturedSink okErr = _CapturedSink();
      final int okExit = await cli.main(
        <String>[
          'deploy',
          'agent_engine',
          '--project=my-gcp-project',
          '--region=us-central1',
          '--update_if_exists',
          agentDir.path,
        ],
        outSink: okOut.sink,
        errSink: okErr.sink,
        environment: const <String, String>{},
        agentEngineClient: client,
      );
      final String okStdout = await okOut.closeAndRead();
      final String okStderr = await okErr.closeAndRead();

      expect(okExit, 0);
      expect(okStdout, contains(existingName));
      expect(okStderr, isEmpty);
      expect(client.createCount, 0);
      expect(client.updates, hasLength(1));
      expect(client.updates.first.$1, existingName);

      // Kebab-case alias also parses updateIfExists=true.
      final DeployCliOptions kebabOpts = parseDeployCliOptions(
        <String>[
          'agent_engine',
          '--project=my-gcp-project',
          '--update-if-exists',
          agentDir.path,
        ],
        env: const <String, String>{},
      );
      expect(kebabOpts.updateIfExists, isTrue);

      // Mutual exclusion with --agent_engine_id fails with usage error and never calls client.
      final _FakeRuntimesClient conflictClient = _FakeRuntimesClient();
      final _CapturedSink badOut = _CapturedSink();
      final _CapturedSink badErr = _CapturedSink();
      final int badExit = await cli.main(
        <String>[
          'deploy',
          'agent_engine',
          '--project=my-gcp-project',
          '--agent_engine_id=123',
          '--update_if_exists',
          agentDir.path,
        ],
        outSink: badOut.sink,
        errSink: badErr.sink,
        environment: const <String, String>{},
        agentEngineClient: conflictClient,
      );
      await badOut.closeAndRead();
      final String badStderr = await badErr.closeAndRead();

      expect(badExit, isNot(0));
      expect(
        badStderr,
        contains('Do not pass both --agent_engine_id and --update_if_exists.'),
      );
      expect(conflictClient.listFilters, isEmpty);
      expect(conflictClient.createCount, 0);
      expect(conflictClient.updates, isEmpty);

      // toAgentEngine also enforces mutual exclusion directly.
      expect(
        () => toAgentEngine(
          DeployCommand(
            service: 'my-agent',
            project: 'my-gcp-project',
            region: 'us-central1',
            image: 'gcr.io/my-gcp-project/my-agent:latest',
            agentEngineId: '123',
            updateIfExists: true,
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            contains('Do not pass both --agent_engine_id and --update_if_exists.'),
          ),
        ),
      );
    });

    test('CLI deploy agent_engine --update_if_exists in Express Mode returns exit code 1', () async {
      final _CapturedSink out = _CapturedSink();
      final _CapturedSink err = _CapturedSink();

      final int exitCode = await cli.main(
        <String>[
          'deploy',
          'agent_engine',
          '--api_key=fake-api-key',
          '--update_if_exists',
          agentDir.path,
        ],
        outSink: out.sink,
        errSink: err.sink,
        environment: const <String, String>{},
      );
      await out.closeAndRead();
      final String stderrText = await err.closeAndRead();

      expect(exitCode, 1);
      expect(stderrText, contains('Express Mode'));
      expect(
        stderrText,
        contains('replace --update_if_exists with --agent_engine_id'),
      );
    });
  });
}
