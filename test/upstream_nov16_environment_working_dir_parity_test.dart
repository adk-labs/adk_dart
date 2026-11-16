import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/integrations/daytona/daytona_environment.dart'
    as integrations_daytona;
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

Context _makeContext({String invocationId = 'inv_nov16'}) {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: invocationId,
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(
      id: 'session_nov16',
      appName: 'app',
      userId: 'user_nov16',
      state: <String, Object?>{},
    ),
  );
  return Context(invocationContext);
}

class _NoWorkingDirEnvironment extends BaseEnvironment {
  @override
  Future<EnvironmentExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
    Context? ctx,
  }) async {
    return const EnvironmentExecutionResult(exitCode: 0);
  }

  @override
  Future<List<int>> readFile(Object path, {Context? ctx}) async => const <int>[];

  @override
  Future<void> writeFile(Object path, Object content, {Context? ctx}) async {}
}

class _FakeEnvironment extends BaseEnvironment {
  _FakeEnvironment({
    this.stdout = '',
    Directory? workingDir,
  }) : _workingDir = workingDir;

  final String stdout;
  Directory? _workingDir;
  int workingDirReadCount = 0;
  int initializeCount = 0;
  int writeFileCount = 0;
  final List<(String, Context?)> contexts = <(String, Context?)>[];
  final Map<String, List<int>> writtenFiles = <String, List<int>>{};

  void setWorkingDir(Directory? dir) {
    _workingDir = dir;
  }

  @override
  Directory? get workingDir {
    workingDirReadCount += 1;
    return _workingDir;
  }

  @override
  Future<void> initialize({Context? ctx}) async {
    initializeCount += 1;
    contexts.add(('initialize', ctx));
    _workingDir ??= Directory('/workspace');
  }

  @override
  Future<void> close() async {
    contexts.add(('close', null));
  }

  @override
  Future<EnvironmentExecutionResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 30),
    Context? ctx,
  }) async {
    contexts.add(('execute', ctx));
    return EnvironmentExecutionResult(
      exitCode: 0,
      stdout: stdout,
      stderr: '',
      timedOut: false,
    );
  }

  @override
  Future<List<int>> readFile(Object path, {Context? ctx}) async {
    contexts.add(('read_file', ctx));
    return writtenFiles['$path'] ?? const <int>[];
  }

  @override
  Future<void> writeFile(Object path, Object content, {Context? ctx}) async {
    writeFileCount += 1;
    contexts.add(('write_file', ctx));
    writtenFiles['$path'] = encodeWriteFileContent(content);
  }
}

class _RaisingBeforeInitEnvironment extends _FakeEnvironment {
  _RaisingBeforeInitEnvironment();

  bool raiseOnWorkingDir = true;

  @override
  Directory get workingDir {
    workingDirReadCount += 1;
    if (raiseOnWorkingDir && _workingDir == null) {
      throw StateError('`working_dir` is not set. Call initialize() first.');
    }
    return _workingDir!;
  }
}

class _FakeDaytonaHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{"id":"daytona-sbx"}')),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}

class _NoopOpenSandboxClient implements OpenSandboxClient {
  bool throwOnClose = false;
  int closeCalls = 0;

  @override
  Future<String> createOrAttachSandbox({
    required String image,
    Duration? timeout,
    Map<String, String>? envVars,
  }) async => 'sbx-open-1';

  @override
  Future<EnvironmentExecutionResult> execute({
    required String sandboxId,
    required String command,
    String? workingDir,
    Duration? timeout,
    Map<String, String>? envVars,
  }) async => const EnvironmentExecutionResult(exitCode: 0);

  @override
  Future<Uint8List> readFile({
    required String sandboxId,
    required String path,
  }) async => Uint8List(0);

  @override
  Future<void> writeFile({
    required String sandboxId,
    required String path,
    required List<int> bytes,
  }) async {}

  @override
  Future<void> closeSandbox(String sandboxId) async {
    closeCalls += 1;
    if (throwOnClose) {
      throw StateError('cleanup failed');
    }
  }
}

class _MutableSkillRegistry extends SkillRegistry {
  final Map<String, Skill> _entries = <String, Skill>{};

  void put(Skill skill) {
    _entries[skill.name] = skill;
  }

  @override
  Future<Skill?> getSkill({required String name, String? version}) async {
    return _entries[name];
  }

  @override
  Future<List<Frontmatter>> searchSkills({
    required String query,
    Map<String, Object?>? filters,
  }) async {
    return _entries.values.map((Skill s) => s.frontmatter).toList();
  }
}

Skill _scriptSkill({
  String name = 'a',
  String instructions = 'Initial skill instructions v1.',
  String scriptSrc = 'print(1)',
}) {
  return Skill(
    frontmatter: Frontmatter(name: name, description: 'Skill $name'),
    instructions: instructions,
    resources: Resources(
      scripts: <String, Script>{'s.py': Script(src: scriptSrc)},
    ),
  );
}

Future<String> _envInstruction(
  EnvironmentToolset toolset, [
  Context? ctx,
]) async {
  final LlmRequest request = LlmRequest();
  await toolset.processLlmRequest(
    toolContext: ctx ?? _makeContext(),
    llmRequest: request,
  );
  return request.config.systemInstruction ?? '';
}

Future<String> _skillInstruction(SkillToolset toolset, [Context? ctx]) async {
  final LlmRequest request = LlmRequest();
  await toolset.processLlmRequest(
    toolContext: ctx ?? _makeContext(),
    llmRequest: request,
  );
  return request.config.systemInstruction ?? '';
}

Future<void> _runExecute(EnvironmentToolset toolset, [Context? ctx]) async {
  final List<BaseTool> tools = await toolset.getTools();
  final BaseTool execute = tools.firstWhere(
    (BaseTool t) => t.name == 'Execute',
  );
  await execute.run(
    args: <String, dynamic>{'command': 'echo ok'},
    toolContext: ctx ?? _makeContext(),
  );
}

void main() {
  group('Upstream d05e48203: working_dir vs is_initialized parity', () {
    test('1. BaseEnvironment subclass without workingDir override defaults to null', () {
      final _NoWorkingDirEnvironment env = _NoWorkingDirEnvironment();
      expect(env.workingDir, isNull);
    });

    group('2. LocalEnvironment workingDir lifecycle', () {
      test(
        'without explicit directory, workingDir is null until initialize creates it and null again after close',
        () async {
          final LocalEnvironment environment = LocalEnvironment();

          final Directory? before = environment.workingDir;
          await environment.initialize();
          final Directory? created = environment.workingDir;
          expect(created, isNotNull);
          expect(created!.existsSync(), isTrue);

          await environment.writeFile('note.txt', 'hello');
          expect(utf8.decode(await environment.readFile('note.txt')), 'hello');

          await environment.close();

          expect(before, isNull);
          expect(environment.workingDir, isNull);
          expect(created.existsSync(), isFalse);
          expect(environment.isInitialized, isFalse);

          // Re-initializing creates a fresh temporary workspace.
          await environment.initialize();
          final Directory? recreated = environment.workingDir;
          expect(recreated, isNotNull);
          expect(recreated!.existsSync(), isTrue);
          await environment.close();
          expect(environment.workingDir, isNull);
          expect(recreated.existsSync(), isFalse);
        },
      );

      test(
        'calling execute/readFile/readFileStream/writeFile before initialize without workingDir throws StateError',
        () async {
          final LocalEnvironment environment = LocalEnvironment();

          await expectLater(
            () => environment.execute('echo hi'),
            throwsA(
              isA<StateError>().having(
                (StateError e) => e.message,
                'message',
                contains('`working_dir` is not set. Call initialize() first.'),
              ),
            ),
          );
          await expectLater(
            () => environment.readFile('a.txt'),
            throwsStateError,
          );
          await expectLater(
            () => environment.readFileStream('a.txt').toList(),
            throwsStateError,
          );
          await expectLater(
            () => environment.writeFile('a.txt', 'hello'),
            throwsStateError,
          );
        },
      );

      test(
        'with explicit workingDirectory, workingDir is known before initialize and preserved across close',
        () async {
          final Directory supplied = await Directory.systemTemp.createTemp(
            'adk_supplied_dir_',
          );
          addTearDown(() async {
            if (supplied.existsSync()) {
              await supplied.delete(recursive: true);
            }
          });

          final LocalEnvironment environment = LocalEnvironment(
            workingDirectory: supplied,
          );
          expect(environment.workingDir?.path, supplied.absolute.path);
          expect(environment.isInitialized, isFalse);

          await environment.initialize();
          await environment.writeFile('keep.txt', 'data');
          await environment.close();

          expect(environment.workingDir?.path, supplied.absolute.path);
          expect(supplied.existsSync(), isTrue);
          expect(File('${supplied.path}/keep.txt').existsSync(), isTrue);
        },
      );
    });

    group('3. Sandbox environments report fixed workingDir before initialize and after close', () {
      test('DaytonaEnvironment (tools & integrations) reports /workspaces before init and after close', () async {
        final DaytonaEnvironment toolsDaytona = DaytonaEnvironment(
          apiKey: 'key',
          httpClient: _FakeDaytonaHttpClient(),
        );
        expect(toolsDaytona.workingDir.path, '/workspaces');
        expect(toolsDaytona.isInitialized, isFalse);
        await toolsDaytona.initialize();
        expect(toolsDaytona.workingDir.path, '/workspaces');
        await toolsDaytona.close();
        expect(toolsDaytona.workingDir.path, '/workspaces');

        final integrations_daytona.DaytonaEnvironment intDaytona =
            integrations_daytona.DaytonaEnvironment(
              apiKey: 'key',
              httpClient: _FakeDaytonaHttpClient(),
            );
        expect(intDaytona.workingDir.path, '/workspaces');
        expect(intDaytona.isInitialized, isFalse);
        await intDaytona.initialize();
        expect(intDaytona.workingDir.path, '/workspaces');
        await intDaytona.close();
        expect(intDaytona.workingDir.path, '/workspaces');
      });

      test('E2BEnvironment reports /home/user before init and after close', () async {
        final E2BEnvironment env = E2BEnvironment(apiKey: 'e2b-key');
        expect(env.workingDir.path, '/home/user');
        expect(env.isInitialized, isFalse);

        // Operations before initialize still require initialize().
        await expectLater(() => env.execute('ls'), throwsStateError);

        await env.initialize();
        expect(env.workingDir.path, '/home/user');
        await env.close();
        expect(env.isInitialized, isFalse);
        expect(env.workingDir.path, '/home/user');
      });

      test('OpenSandboxEnvironment reports /workspace before init, after close, and if close raises', () async {
        final _NoopOpenSandboxClient client = _NoopOpenSandboxClient();
        final OpenSandboxEnvironment env = OpenSandboxEnvironment(
          client: client,
        );
        expect(env.workingDir.path, '/workspace');
        expect(env.isInitialized, isFalse);

        await env.initialize();
        expect(env.workingDir.path, '/workspace');

        client.throwOnClose = true;
        await expectLater(env.close(), throwsStateError);
        expect(env.isInitialized, isFalse);
        expect(env.workingDir.path, '/workspace');

        // Idempotent second close.
        await env.close();
        expect(client.closeCalls, 1);
      });

      test('AgentEngineEnvironment reports /workspace before init and after close', () async {
        final AgentEngineEnvironment env = AgentEngineEnvironment(
          agentEngineResourceName:
              'projects/my-proj/locations/us-central1/reasoningEngines/1',
        );
        expect(env.workingDir.path, '/workspace');
        expect(env.isInitialized, isFalse);

        await env.initialize();
        expect(env.workingDir.path, '/workspace');
        await env.close();
        expect(env.isInitialized, isFalse);
        expect(env.workingDir.path, '/workspace');
      });
    });

    group('4. EnvironmentToolset workingDir instruction behavior', () {
      test('omits working directory when workingDir is null without initializing', () async {
        final _FakeEnvironment env = _FakeEnvironment();
        final EnvironmentToolset toolset = EnvironmentToolset(environment: env);

        final String instruction = await _envInstruction(toolset);

        expect(env.contexts, isEmpty);
        expect(instruction, contains('# Environment Rules'));
        expect(instruction, isNot(contains('Your environment is at')));
      });

      test('includes working directory once a tool call initializes the environment', () async {
        final _FakeEnvironment env = _FakeEnvironment();
        final EnvironmentToolset toolset = EnvironmentToolset(environment: env);
        await _runExecute(toolset);

        final String instruction = await _envInstruction(toolset);

        expect(instruction, contains('Your environment is at /workspace/'));
        expect(instruction, contains('# Environment Rules'));
      });

      test('includes working directory immediately before initialization when known', () async {
        final _FakeEnvironment env = _FakeEnvironment(
          workingDir: Directory('/workspace'),
        );
        final EnvironmentToolset toolset = EnvironmentToolset(environment: env);

        final String instruction = await _envInstruction(toolset);

        expect(instruction, contains('Your environment is at /workspace/'));
        expect(instruction, contains('# Environment Rules'));
        expect(env.contexts, isEmpty);
        expect(env.isInitialized, isFalse);
      });

      test('shows sandbox working directory on the first request for remote sandboxes', () async {
        final DaytonaEnvironment daytona = DaytonaEnvironment(apiKey: 'k');
        final E2BEnvironment e2b = E2BEnvironment(apiKey: 'k');
        final OpenSandboxEnvironment opensandbox = OpenSandboxEnvironment(
          client: _NoopOpenSandboxClient(),
        );
        final AgentEngineEnvironment agentEngine = AgentEngineEnvironment(
          agentEngineResourceName: 'projects/p/locations/l/reasoningEngines/1',
        );

        expect(
          await _envInstruction(EnvironmentToolset(environment: daytona)),
          startsWith('Your environment is at /workspaces/\n'),
        );
        expect(
          await _envInstruction(EnvironmentToolset(environment: e2b)),
          startsWith('Your environment is at /home/user/\n'),
        );
        expect(
          await _envInstruction(EnvironmentToolset(environment: opensandbox)),
          startsWith('Your environment is at /workspace/\n'),
        );
        expect(
          await _envInstruction(EnvironmentToolset(environment: agentEngine)),
          startsWith('Your environment is at /workspace/\n'),
        );
        expect(daytona.isInitialized, isFalse);
        expect(e2b.isInitialized, isFalse);
        expect(opensandbox.isInitialized, isFalse);
        expect(agentEngine.isInitialized, isFalse);
      });

      test('tolerates workingDir throwing StateError before initialization', () async {
        final _RaisingBeforeInitEnvironment env =
            _RaisingBeforeInitEnvironment();
        expect(workingDirOrNone(env), isNull);

        final EnvironmentToolset toolset = EnvironmentToolset(environment: env);

        final String before = await _envInstruction(toolset);
        await _runExecute(toolset);
        final String after = await _envInstruction(toolset);

        expect(before, contains('# Environment Rules'));
        expect(before, isNot(contains('Your environment is at')));
        expect(after, contains('Your environment is at /workspace/'));
      });
    });

    group('5. SkillToolset skillsFolder & processLlmRequest parity', () {
      test(
        'omits skillsFolder while workingDir is null and includes it once workingDir is set even while isInitialized stays false',
        () async {
          final _FakeEnvironment env = _FakeEnvironment();
          final SkillToolset toolset = SkillToolset(
            skills: <Skill>[_scriptSkill()],
            environment: env,
          );

          expect(toolset.skillsFolder, isNull);
          final String before = await _skillInstruction(toolset);

          // Only set workingDir; isInitialized stays false.
          env.setWorkingDir(Directory('/workspace'));
          expect(env.isInitialized, isFalse);
          expect(toolset.skillsFolder, '/workspace/skills');
          final String after = await _skillInstruction(toolset);

          expect(env.initializeCount, 0);
          expect(before, isNot(contains('/workspace/skills/<skill_name>/')));
          expect(after, contains('/workspace/skills/<skill_name>/'));
        },
      );

      test('tolerates workingDir throwing StateError before initialization', () async {
        final _RaisingBeforeInitEnvironment env =
            _RaisingBeforeInitEnvironment();
        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[_scriptSkill()],
          environment: env,
        );

        expect(toolset.skillsFolder, isNull);
        final String before = await _skillInstruction(toolset);

        // Give env its working directory while isInitialized remains false.
        env.setWorkingDir(Directory('/workspace'));
        expect(env.isInitialized, isFalse);
        expect(toolset.skillsFolder, '/workspace/skills');
        final String after = await _skillInstruction(toolset);

        expect(env.initializeCount, 0);
        expect(before, isNot(contains('/workspace/skills/<skill_name>/')));
        expect(after, contains('/workspace/skills/<skill_name>/'));
      });

      test('keeps explicit skillsFolder before initialization even when workingDir is null or throws', () async {
        final _RaisingBeforeInitEnvironment env =
            _RaisingBeforeInitEnvironment();
        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[_scriptSkill()],
          environment: env,
          skillsFolder: '/opt/custom_skills',
        );

        expect(toolset.skillsFolder, '/opt/custom_skills');
        final String instruction = await _skillInstruction(toolset);
        expect(instruction, contains('/opt/custom_skills/<skill_name>/'));
        expect(env.initializeCount, 0);
      });

      test('run_skill_script initializes environment first and stages under workingDir/skills', () async {
        final _FakeEnvironment env = _FakeEnvironment(stdout: '1\n');
        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[_scriptSkill()],
          environment: env,
        );
        final Context ctx = _makeContext(invocationId: 'inv_run_script');
        final BaseTool runTool = RunSkillScriptTool(toolset);

        final Map<String, Object?> res =
            (await runTool.run(
                  args: <String, dynamic>{
                    'skill_name': 'a',
                    'file_path': 'scripts/s.py',
                  },
                  toolContext: ctx,
                ) as Map)
                .cast<String, Object?>();

        expect(res['status'], 'success');
        expect(env.initializeCount, 1);
        expect(env.contexts.first, ('initialize', ctx));
        expect(
          env.writtenFiles.keys,
          contains('/workspace/skills/a/scripts/s.py'),
        );
      });

      test('changed skill leaves an uninitialized workingDir==null environment alone', () async {
        final _FakeEnvironment env = _FakeEnvironment();
        final _MutableSkillRegistry registry = _MutableSkillRegistry()
          ..put(
            _scriptSkill(
              name: 'a',
              instructions: 'Version 1 instructions.',
              scriptSrc: 'print(1)',
            ),
          );
        final SkillToolset toolset = SkillToolset(
          registry: registry,
          environment: env,
          lifecycleConfig: SkillLifecycleConfig(
            enabled: true,
            revalidateSkills: true,
          ),
        );
        final Context ctx = _makeContext(invocationId: 'inv_turn_1');
        await LoadSkillTool(toolset).run(
          args: <String, dynamic>{'skill_name': 'a'},
          toolContext: ctx,
        );

        // Mutate skill in registry for the next turn while env remains uninitialized.
        registry.put(
          _scriptSkill(
            name: 'a',
            instructions: 'Version 2 updated instructions.',
            scriptSrc: 'print(2)',
          ),
        );
        env.workingDirReadCount = 0;

        final Context ctx2 = Context(
          InvocationContext(
            sessionService: ctx.invocationContext.sessionService,
            invocationId: 'inv_turn_2',
            agent: ctx.invocationContext.agent,
            session: ctx.session,
          ),
        );
        final String instruction = await _skillInstruction(toolset, ctx2);

        expect(instruction, contains('The skill `a` has changed'));
        expect(instruction, contains('Version 2 updated instructions.'));
        expect(env.initializeCount, 0);
        expect(env.writeFileCount, 0);
      });
    });
  });
}
