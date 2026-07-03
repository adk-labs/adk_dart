import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

Context _newToolContext() {
  final InvocationContext invocationContext = InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_skill_toolset',
    agent: LlmAgent(name: 'root', instruction: 'root'),
    session: Session(
      id: 's_skill_toolset',
      appName: 'app',
      userId: 'u1',
      state: <String, Object?>{},
    ),
  );
  return Context(invocationContext);
}

Skill _sampleSkill() {
  return Skill(
    frontmatter: Frontmatter(
      name: 'my-skill',
      description: 'Helpful specialized workflow',
      extraFields: <String, Object?>{'x-extra': 'custom'},
    ),
    instructions: 'Follow these steps carefully.',
    resources: Resources(
      references: <String, String>{'guide.md': 'reference doc'},
      assets: <String, String>{'template.txt': 'asset template'},
      scripts: <String, Script>{'setup.sh': Script(src: 'echo setup')},
    ),
  );
}

Skill _skillWithAdditionalTool() {
  return Skill(
    frontmatter: Frontmatter(
      name: 'dynamic-skill',
      description: 'Unlocks an additional tool after activation',
      metadata: <String, Object?>{
        'adk_additional_tools': <String>['extra_tool'],
      },
    ),
    instructions: 'Load me before using the extra tool.',
    resources: Resources(
      references: <String, Object>{'guide.md': 'dynamic guide'},
    ),
  );
}

Skill _binarySkill() {
  return Skill(
    frontmatter: Frontmatter(
      name: 'binary-skill',
      description: 'Contains a binary asset',
    ),
    instructions: 'Use the binary asset when needed.',
    resources: Resources(
      assets: <String, Object>{
        'document.pdf': <int>[37, 80, 68, 70],
      },
    ),
  );
}

class _FakeCodeExecutor extends BaseCodeExecutor {
  _FakeCodeExecutor(this.result);

  final CodeExecutionResult result;
  String? lastCode;
  String? lastExecuteType;

  @override
  Future<CodeExecutionResult> execute(CodeExecutionRequest request) async {
    lastCode = request.command;
    return result;
  }

  @override
  Future<CodeExecutionResult> executeCode(
    InvocationContext invocationContext,
    CodeExecutionInput codeExecutionInput,
  ) async {
    lastCode = codeExecutionInput.code;
    lastExecuteType = codeExecutionInput.executeType;
    return result;
  }
}

class _FakeAdditionalTool extends BaseTool {
  _FakeAdditionalTool()
    : super(name: 'extra_tool', description: 'Extra tool exposed by skill');

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, Object?>{'status': 'ok'};
  }
}

class _FakeAdditionalToolset extends BaseToolset {
  _FakeAdditionalToolset(this.tools);

  final List<BaseTool> tools;
  int getToolsWithPrefixCalls = 0;
  int closeCalls = 0;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    return tools;
  }

  @override
  Future<List<BaseTool>> getToolsWithPrefix({
    ReadonlyContext? readonlyContext,
  }) async {
    getToolsWithPrefixCalls += 1;
    return super.getToolsWithPrefix(readonlyContext: readonlyContext);
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}

class _RecordingSkillRegistry extends SkillRegistry {
  _RecordingSkillRegistry(Iterable<Skill> skills) {
    for (final Skill skill in skills) {
      register(skill);
    }
  }

  int getSkillCalls = 0;
  int searchSkillsCalls = 0;

  @override
  Future<Skill?> getSkill({required String name, String? version}) async {
    getSkillCalls += 1;
    return super.getSkill(name: name, version: version);
  }

  @override
  Future<List<Frontmatter>> searchSkills({
    required String query,
    Map<String, Object?>? filters,
  }) async {
    searchSkillsCalls += 1;
    return list().map((Skill skill) => skill.frontmatter).toList();
  }

  @override
  Map<String, Object?>? getFilterSchema() {
    return <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'domain': <String, Object?>{'type': 'string'},
      },
    };
  }

  @override
  String getSearchDescription() {
    return 'Search registry skills for this test.';
  }
}

void main() {
  group('SkillToolset parity', () {
    test('rejects duplicate skill names', () {
      final Skill skill = _sampleSkill();
      expect(
        () => SkillToolset(skills: <Skill>[skill, skill]),
        throwsArgumentError,
      );
    });

    test('getTools returns list/load/resource tools', () async {
      final SkillToolset toolset = SkillToolset(
        skills: <Skill>[_sampleSkill()],
      );
      final List<BaseTool> tools = await toolset.getTools();
      expect(tools.map((BaseTool tool) => tool.name).toList(), <String>[
        'list_skills',
        'load_skill',
        'load_skill_resource',
        'run_skill_script',
      ]);
      expect(tools[0], isA<ListSkillsTool>());
      expect(tools[1], isA<LoadSkillTool>());
      expect(tools[2], isA<LoadSkillResourceTool>());
      expect(tools[3], isA<RunSkillScriptTool>());
    });

    test(
      'getTools includes search_skills when registry is configured',
      () async {
        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[_sampleSkill()],
          registry: _RecordingSkillRegistry(<Skill>[
            _skillWithAdditionalTool(),
          ]),
        );
        final List<BaseTool> tools = await toolset.getTools();
        expect(
          tools.map((BaseTool tool) => tool.name),
          contains('search_skills'),
        );

        final BaseTool searchTool = tools.singleWhere(
          (BaseTool tool) => tool.name == 'search_skills',
        );
        expect(searchTool, isA<SearchSkillsTool>());
        final Map<String, dynamic> parameters = searchTool
            .getDeclaration()!
            .parameters;
        expect(parameters['properties'].toString(), contains('filters'));
      },
    );

    test('public skill tools can be constructed standalone', () async {
      final SkillToolset toolset = SkillToolset(
        skills: <Skill>[_sampleSkill()],
        registry: _RecordingSkillRegistry(<Skill>[_skillWithAdditionalTool()]),
      );
      final ToolContext toolContext = _newToolContext();

      final Object? listed = await ListSkillsTool(
        toolset,
      ).run(args: <String, dynamic>{}, toolContext: toolContext);
      expect('$listed', contains('my-skill'));

      final Object? loaded = await LoadSkillTool(toolset).run(
        args: <String, dynamic>{'skill_name': 'my-skill'},
        toolContext: toolContext,
      );
      expect(
        Map<String, Object?>.from(loaded! as Map)['skill_name'],
        'my-skill',
      );

      final Object? resource = await LoadSkillResourceTool(toolset).run(
        args: <String, dynamic>{
          'skill_name': 'my-skill',
          'file_path': 'references/guide.md',
        },
        toolContext: toolContext,
      );
      expect(
        Map<String, Object?>.from(resource! as Map)['content'],
        'reference doc',
      );

      final Object? searched = await SearchSkillsTool(toolset).run(
        args: <String, dynamic>{'query': 'dynamic'},
        toolContext: toolContext,
      );
      expect(
        Map<String, Object?>.from(
          List<Object?>.from(searched! as List).single! as Map,
        )['name'],
        'dynamic-skill',
      );

      expect(
        () => SearchSkillsTool(SkillToolset(skills: <Skill>[_sampleSkill()])),
        throwsArgumentError,
      );
    });

    test('supports tool filter and prefix-aware instructions', () async {
      final SkillToolset toolset = SkillToolset(
        skills: <Skill>[_sampleSkill()],
        registry: _RecordingSkillRegistry(<Skill>[_skillWithAdditionalTool()]),
        toolNamePrefix: 'skill',
        toolFilter: <String>['load_skill', 'search_skills'],
      );

      final List<BaseTool> rawTools = await toolset.getTools();
      expect(rawTools.map((BaseTool tool) => tool.name).toList(), <String>[
        'load_skill',
        'search_skills',
      ]);

      final List<BaseTool> prefixedTools = await toolset.getToolsWithPrefix();
      expect(prefixedTools.map((BaseTool tool) => tool.name).toList(), <String>[
        'skill_load_skill',
        'skill_search_skills',
      ]);

      final LlmRequest request = LlmRequest(model: 'gemini-2.5-flash');
      await toolset.processLlmRequest(
        toolContext: _newToolContext(),
        llmRequest: request,
      );

      final String instruction = request.config.systemInstruction!;
      expect(instruction, contains('`skill_load_skill`'));
      expect(instruction, contains('`skill_load_skill` tool'));
      expect(instruction, contains('`skill_search_skills`'));
      expect(instruction, isNot(contains('`load_skill` tool')));
      expect(instruction, contains('do not retry any path'));
    });

    test('load_skill returns not found for missing local skill', () async {
      final SkillToolset toolset = SkillToolset(skills: <Skill>[]);
      final List<BaseTool> tools = await toolset.getTools();
      final BaseTool loadTool = tools[1];

      final Object? result = await loadTool.run(
        args: <String, dynamic>{'skill_name': 'missing-skill'},
        toolContext: _newToolContext(),
      );
      final Map<String, Object?> payload = Map<String, Object?>.from(
        result! as Map,
      );
      expect(payload['error_code'], 'SKILL_NOT_FOUND');
    });

    test('list_skills returns xml-formatted skill descriptor', () async {
      final SkillToolset toolset = SkillToolset(
        skills: <Skill>[_sampleSkill()],
      );
      final BaseTool listTool = (await toolset.getTools()).first;

      final Object? result = await listTool.run(
        args: <String, dynamic>{},
        toolContext: _newToolContext(),
      );
      expect(result, isA<String>());
      expect('$result', contains('<available_skills>'));
      expect('$result', contains('<name>'));
      expect('$result', contains('my-skill'));
    });

    test('load_skill returns instructions and frontmatter', () async {
      final SkillToolset toolset = SkillToolset(
        skills: <Skill>[_sampleSkill()],
      );
      final BaseTool loadTool = (await toolset.getTools())[1];

      final Object? result = await loadTool.run(
        args: <String, dynamic>{'skill_name': 'my-skill'},
        toolContext: _newToolContext(),
      );

      final Map<String, Object?> payload = Map<String, Object?>.from(
        result! as Map,
      );
      expect(payload['skill_name'], 'my-skill');
      expect(payload['instructions'], 'Follow these steps carefully.');
      final Map<String, Object?> frontmatter = Map<String, Object?>.from(
        payload['frontmatter']! as Map,
      );
      expect(frontmatter['name'], 'my-skill');
      expect(frontmatter['description'], 'Helpful specialized workflow');
      expect(frontmatter['x-extra'], 'custom');
    });

    test(
      'search_skills returns registry frontmatter and filters local conflicts',
      () async {
        final _RecordingSkillRegistry registry = _RecordingSkillRegistry(
          <Skill>[_sampleSkill(), _skillWithAdditionalTool()],
        );
        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[_sampleSkill()],
          registry: registry,
        );
        final BaseTool searchTool = (await toolset.getTools()).singleWhere(
          (BaseTool tool) => tool.name == 'search_skills',
        );

        final Object? result = await searchTool.run(
          args: <String, dynamic>{
            'query': 'dynamic',
            'filters': <String, Object?>{'domain': 'test'},
          },
          toolContext: _newToolContext(),
        );

        final List<Object?> payload = List<Object?>.from(result! as List);
        expect(registry.searchSkillsCalls, 1);
        expect(payload, hasLength(1));
        expect(
          Map<String, Object?>.from(payload.single! as Map)['name'],
          'dynamic-skill',
        );
      },
    );

    test('load_skill fetches registry skills once per invocation', () async {
      final _RecordingSkillRegistry registry = _RecordingSkillRegistry(<Skill>[
        _skillWithAdditionalTool(),
      ]);
      final SkillToolset toolset = SkillToolset(
        registry: registry,
        additionalTools: <BaseTool>[_FakeAdditionalTool()],
      );
      final Context toolContext = _newToolContext();
      final BaseTool loadTool = (await toolset.getTools())[1];

      final Object? first = await loadTool.run(
        args: <String, dynamic>{'skill_name': 'dynamic-skill'},
        toolContext: toolContext,
      );
      final Object? second = await loadTool.run(
        args: <String, dynamic>{'skill_name': 'dynamic-skill'},
        toolContext: toolContext,
      );

      expect(
        Map<String, Object?>.from(first! as Map)['skill_name'],
        'dynamic-skill',
      );
      expect(
        Map<String, Object?>.from(second! as Map)['skill_name'],
        'dynamic-skill',
      );
      expect(registry.getSkillCalls, 1);

      final List<BaseTool> resolved = await toolset.getTools(
        readonlyContext: ReadonlyContext(toolContext.invocationContext),
      );
      expect(
        resolved.map((BaseTool tool) => tool.name),
        contains('extra_tool'),
      );
    });

    test(
      'load_skill records activated skill state for dynamic tool resolution',
      () async {
        final Context toolContext = _newToolContext();
        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[_skillWithAdditionalTool()],
          additionalTools: <BaseTool>[_FakeAdditionalTool()],
        );
        final BaseTool loadTool = (await toolset.getTools())[1];

        await loadTool.run(
          args: <String, dynamic>{'skill_name': 'dynamic-skill'},
          toolContext: toolContext,
        );

        final List<Object?> activated = List<Object?>.from(
          toolContext.state['_adk_activated_skill_root'] as List,
        );
        expect(activated, <String>['dynamic-skill']);

        final List<BaseTool> resolved = await toolset.getTools(
          readonlyContext: ReadonlyContext(toolContext.invocationContext),
        );
        expect(
          resolved.map((BaseTool tool) => tool.name),
          contains('extra_tool'),
        );
      },
    );

    test(
      'resolves activated additional tools from provided toolsets',
      () async {
        final Context toolContext = _newToolContext();
        final _FakeAdditionalToolset providedToolset = _FakeAdditionalToolset(
          <BaseTool>[_FakeAdditionalTool()],
        );
        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[_skillWithAdditionalTool()],
          additionalTools: <Object>[providedToolset],
        );
        final BaseTool loadTool = (await toolset.getTools())[1];

        await loadTool.run(
          args: <String, dynamic>{'skill_name': 'dynamic-skill'},
          toolContext: toolContext,
        );

        final List<BaseTool> resolved = await toolset.getTools(
          readonlyContext: ReadonlyContext(toolContext.invocationContext),
        );

        expect(
          resolved.map((BaseTool tool) => tool.name),
          contains('extra_tool'),
        );
        expect(providedToolset.getToolsWithPrefixCalls, 1);
      },
    );

    test('close clears registry cache and closes provided toolsets', () async {
      final Context toolContext = _newToolContext();
      final _RecordingSkillRegistry registry = _RecordingSkillRegistry(<Skill>[
        _skillWithAdditionalTool(),
      ]);
      final _FakeAdditionalToolset providedToolset = _FakeAdditionalToolset(
        <BaseTool>[_FakeAdditionalTool()],
      );
      final SkillToolset toolset = SkillToolset(
        registry: registry,
        additionalTools: <Object>[providedToolset],
      );
      final BaseTool loadTool = (await toolset.getTools())[1];

      await loadTool.run(
        args: <String, dynamic>{'skill_name': 'dynamic-skill'},
        toolContext: toolContext,
      );
      expect(registry.getSkillCalls, 1);

      await toolset.close();
      expect(providedToolset.closeCalls, 1);

      await loadTool.run(
        args: <String, dynamic>{'skill_name': 'dynamic-skill'},
        toolContext: toolContext,
      );
      expect(registry.getSkillCalls, 2);
    });

    test('load_skill returns missing/not-found errors', () async {
      final SkillToolset toolset = SkillToolset(
        skills: <Skill>[_sampleSkill()],
      );
      final BaseTool loadTool = (await toolset.getTools())[1];

      final Object? missing = await loadTool.run(
        args: <String, dynamic>{},
        toolContext: _newToolContext(),
      );
      final Map<String, Object?> missingPayload = Map<String, Object?>.from(
        missing! as Map,
      );
      expect(missingPayload['error_code'], 'INVALID_ARGUMENTS');

      final Object? notFound = await loadTool.run(
        args: <String, dynamic>{'skill_name': 'unknown-skill'},
        toolContext: _newToolContext(),
      );
      final Map<String, Object?> notFoundPayload = Map<String, Object?>.from(
        notFound! as Map,
      );
      expect(notFoundPayload['error_code'], 'SKILL_NOT_FOUND');
    });

    test(
      'load_skill_resource returns reference/asset/script content',
      () async {
        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[_sampleSkill()],
        );
        final BaseTool resourceTool = (await toolset.getTools())[2];

        final Object? reference = await resourceTool.run(
          args: <String, dynamic>{
            'skill_name': 'my-skill',
            'file_path': 'references/guide.md',
          },
          toolContext: _newToolContext(),
        );
        expect(
          Map<String, Object?>.from(reference! as Map)['content'],
          'reference doc',
        );

        final Object? asset = await resourceTool.run(
          args: <String, dynamic>{
            'skill_name': 'my-skill',
            'file_path': 'assets/template.txt',
          },
          toolContext: _newToolContext(),
        );
        expect(
          Map<String, Object?>.from(asset! as Map)['content'],
          'asset template',
        );

        final Object? script = await resourceTool.run(
          args: <String, dynamic>{
            'skill_name': 'my-skill',
            'file_path': 'scripts/setup.sh',
          },
          toolContext: _newToolContext(),
        );
        expect(
          Map<String, Object?>.from(script! as Map)['content'],
          'echo setup',
        );
      },
    );

    test(
      'load_skill_resource returns binary status for binary assets',
      () async {
        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[_binarySkill()],
        );
        final BaseTool resourceTool = (await toolset.getTools())[2];

        final Object? asset = await resourceTool.run(
          args: <String, dynamic>{
            'skill_name': 'binary-skill',
            'file_path': 'assets/document.pdf',
          },
          toolContext: _newToolContext(),
        );
        final Map<String, Object?> payload = Map<String, Object?>.from(
          asset! as Map,
        );
        expect(payload['status'], contains('Binary file detected'));
        expect(payload.containsKey('content'), isFalse);
      },
    );

    test('load_skill_resource returns path/lookup errors', () async {
      final SkillToolset toolset = SkillToolset(
        skills: <Skill>[_sampleSkill()],
      );
      final BaseTool resourceTool = (await toolset.getTools())[2];

      final Object? invalidPath = await resourceTool.run(
        args: <String, dynamic>{
          'skill_name': 'my-skill',
          'file_path': 'other/file.txt',
        },
        toolContext: _newToolContext(),
      );
      expect(
        Map<String, Object?>.from(invalidPath! as Map)['error_code'],
        'INVALID_RESOURCE_PATH',
      );

      final Object? missingResource = await resourceTool.run(
        args: <String, dynamic>{
          'skill_name': 'my-skill',
          'file_path': 'references/missing.md',
        },
        toolContext: _newToolContext(),
      );
      expect(
        Map<String, Object?>.from(missingResource! as Map)['error_code'],
        'RESOURCE_NOT_FOUND',
      );
    });

    test('load_skill_resource escalates repeated lookup misses', () async {
      final SkillToolset toolset = SkillToolset(
        skills: <Skill>[_sampleSkill()],
      );
      final BaseTool resourceTool = (await toolset.getTools())[2];
      final ToolContext toolContext = _newToolContext();

      final Object? first = await resourceTool.run(
        args: <String, dynamic>{
          'skill_name': 'my-skill',
          'file_path': 'references/missing.md',
        },
        toolContext: toolContext,
      );
      expect(
        Map<String, Object?>.from(first! as Map)['error_code'],
        'RESOURCE_NOT_FOUND',
      );

      final Object? second = await resourceTool.run(
        args: <String, dynamic>{
          'skill_name': 'my-skill',
          'file_path': 'assets/also-missing.txt',
        },
        toolContext: toolContext,
      );
      final Map<String, Object?> payload = Map<String, Object?>.from(
        second! as Map,
      );
      expect(payload['error_code'], 'RESOURCE_NOT_FOUND_FATAL');
      expect('${payload['error']}', contains('Do not retry any path'));
      expect(
        resourceTool.detectErrorInResponse(payload),
        'RESOURCE_NOT_FOUND_FATAL',
      );
    });

    test(
      'run_skill_script returns no executor error when unavailable',
      () async {
        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[_sampleSkill()],
        );
        final BaseTool runTool = (await toolset.getTools())[3];

        final Object? result = await runTool.run(
          args: <String, Object?>{
            'skill_name': 'my-skill',
            'file_path': 'scripts/setup.sh',
          },
          toolContext: _newToolContext(),
        );
        expect(
          Map<String, Object?>.from(result! as Map)['error_code'],
          'NO_CODE_EXECUTOR',
        );
      },
    );

    test('run_skill_script executes using configured code executor', () async {
      final _FakeCodeExecutor fakeExecutor = _FakeCodeExecutor(
        CodeExecutionResult(
          stdout:
              '{"__shell_result__":true,"stdout":"done","stderr":"","returncode":0}',
          stderr: '',
          exitCode: 0,
        ),
      );
      final SkillToolset toolset = SkillToolset(
        skills: <Skill>[_sampleSkill()],
        codeExecutor: fakeExecutor,
      );
      final BaseTool runTool = (await toolset.getTools())[3];

      final Object? result = await runTool.run(
        args: <String, Object?>{
          'skill_name': 'my-skill',
          'file_path': 'scripts/setup.sh',
          'args': <String, Object?>{'name': 'dart'},
        },
        toolContext: _newToolContext(),
      );
      final Map<String, Object?> payload = Map<String, Object?>.from(
        result! as Map,
      );
      expect(payload['status'], 'success');
      expect(payload['stdout'], 'done');
      expect(payload['file_path'], 'scripts/setup.sh');
      expect(fakeExecutor.lastCode, contains('scripts/setup.sh'));
      expect(fakeExecutor.lastCode, contains('--name'));
      expect(fakeExecutor.lastCode, contains('dart'));
    });

    test(
      'run_skill_script materializes short options and positional args',
      () async {
        final _FakeCodeExecutor fakeExecutor = _FakeCodeExecutor(
          CodeExecutionResult(
            stdout:
                '{"__shell_result__":true,"stdout":"done","stderr":"","returncode":0}',
            stderr: '',
            exitCode: 0,
          ),
        );
        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[_sampleSkill()],
          codeExecutor: fakeExecutor,
        );
        final BaseTool runTool = (await toolset.getTools())[3];

        final Object? result = await runTool.run(
          args: <String, Object?>{
            'skill_name': 'my-skill',
            'file_path': 'scripts/setup.sh',
            'args': <String, Object?>{'name': 'dart'},
            'short_options': <String, Object?>{'n': 5},
            'positional_args': <String>['input.txt', 'output.txt'],
          },
          toolContext: _newToolContext(),
        );

        final Map<String, Object?> payload = Map<String, Object?>.from(
          result! as Map,
        );
        expect(payload['status'], 'success');
        expect(fakeExecutor.lastCode, contains('--name'));
        expect(fakeExecutor.lastCode, contains('-n'));
        expect(fakeExecutor.lastCode, contains('"--"'));
        expect(fakeExecutor.lastCode, contains('input.txt'));
        expect(fakeExecutor.lastCode, contains('output.txt'));
      },
    );

    test('run_skill_script validates args and related option types', () async {
      final SkillToolset toolset = SkillToolset(
        skills: <Skill>[_sampleSkill()],
        codeExecutor: _FakeCodeExecutor(
          CodeExecutionResult(stdout: '', stderr: '', exitCode: 0),
        ),
      );
      final BaseTool runTool = (await toolset.getTools())[3];

      final Object? invalidShortOptions = await runTool.run(
        args: <String, Object?>{
          'skill_name': 'my-skill',
          'file_path': 'scripts/setup.sh',
          'short_options': <String>['n'],
        },
        toolContext: _newToolContext(),
      );
      expect(
        Map<String, Object?>.from(invalidShortOptions! as Map)['error_code'],
        'INVALID_ARGUMENTS',
      );

      final Object? invalidPositionalArgs = await runTool.run(
        args: <String, Object?>{
          'skill_name': 'my-skill',
          'file_path': 'scripts/setup.sh',
          'positional_args': <String, Object?>{'file': 'input.txt'},
        },
        toolContext: _newToolContext(),
      );
      expect(
        Map<String, Object?>.from(invalidPositionalArgs! as Map)['error_code'],
        'INVALID_ARGUMENTS',
      );

      final Object? invalidArgs = await runTool.run(
        args: <String, Object?>{
          'skill_name': 'my-skill',
          'file_path': 'scripts/setup.sh',
          'args': 'bad-args',
        },
        toolContext: _newToolContext(),
      );
      expect(
        Map<String, Object?>.from(invalidArgs! as Map)['error_code'],
        'INVALID_ARGUMENTS',
      );
    });

    test(
      'run_skill_script accepts list args and rejects extra option groups',
      () async {
        final _FakeCodeExecutor fakeExecutor = _FakeCodeExecutor(
          CodeExecutionResult(
            stdout:
                '{"__shell_result__":true,"stdout":"done","stderr":"","returncode":0}',
            stderr: '',
            exitCode: 0,
          ),
        );
        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[_sampleSkill()],
          codeExecutor: fakeExecutor,
        );
        final BaseTool runTool = (await toolset.getTools())[3];

        final Object? success = await runTool.run(
          args: <String, Object?>{
            'skill_name': 'my-skill',
            'file_path': 'scripts/setup.sh',
            'args': <String>['-n', '5', 'input.txt'],
          },
          toolContext: _newToolContext(),
        );
        expect(Map<String, Object?>.from(success! as Map)['status'], 'success');
        expect(
          fakeExecutor.lastCode,
          contains('["bash","scripts/setup.sh","-n","5","input.txt"]'),
        );

        final Object? invalid = await runTool.run(
          args: <String, Object?>{
            'skill_name': 'my-skill',
            'file_path': 'scripts/setup.sh',
            'args': <String>['arg1', 'arg2'],
            'short_options': <String, Object?>{'v': true},
            'positional_args': <String>['pos1'],
          },
          toolContext: _newToolContext(),
        );
        final Map<String, Object?> invalidPayload = Map<String, Object?>.from(
          invalid! as Map,
        );
        expect(invalidPayload['error_code'], 'INVALID_ARGUMENTS');
        expect(
          '${invalidPayload['error']}',
          contains("Cannot specify 'short_options' or 'positional_args'"),
        );
      },
    );

    test('supports legacy skill tool argument aliases', () async {
      final SkillToolset toolset = SkillToolset(
        skills: <Skill>[_sampleSkill()],
        codeExecutor: _FakeCodeExecutor(
          CodeExecutionResult(
            stdout:
                '{"__shell_result__":true,"stdout":"done","stderr":"","returncode":0}',
            stderr: '',
            exitCode: 0,
          ),
        ),
      );
      final List<BaseTool> tools = await toolset.getTools();

      final Object? loadResult = await tools[1].run(
        args: <String, Object?>{'name': 'my-skill'},
        toolContext: _newToolContext(),
      );
      expect(
        Map<String, Object?>.from(loadResult! as Map)['skill_name'],
        'my-skill',
      );

      final Object? resourceResult = await tools[2].run(
        args: <String, Object?>{
          'skill_name': 'my-skill',
          'path': 'references/guide.md',
        },
        toolContext: _newToolContext(),
      );
      expect(
        Map<String, Object?>.from(resourceResult! as Map)['file_path'],
        'references/guide.md',
      );

      final Object? runResult = await tools[3].run(
        args: <String, Object?>{
          'skill_name': 'my-skill',
          'script_path': 'scripts/setup.sh',
        },
        toolContext: _newToolContext(),
      );
      expect(Map<String, Object?>.from(runResult! as Map)['status'], 'success');
    });

    test(
      'processLlmRequest appends default system instruction and skills xml',
      () async {
        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[_sampleSkill()],
        );
        final LlmRequest request = LlmRequest(model: 'gemini-2.5-flash');

        await toolset.processLlmRequest(
          toolContext: _newToolContext(),
          llmRequest: request,
        );

        final String? instruction = request.config.systemInstruction;
        expect(instruction, isNotNull);
        expect(instruction!, contains("You can use specialized 'skills'"));
        expect(instruction, contains('run_skill_script'));
        expect(instruction, isNot(contains('run_skill_inline_script')));
        expect(instruction, isNot(contains('search_skills')));
        expect(instruction, isNot(contains('<available_skills>')));
        expect(instruction, isNot(contains('my-skill')));
      },
    );

    test(
      'processLlmRequest appends registry search guidance when configured',
      () async {
        final SkillToolset toolset = SkillToolset(
          registry: _RecordingSkillRegistry(<Skill>[
            _skillWithAdditionalTool(),
          ]),
        );
        final LlmRequest request = LlmRequest(model: 'gemini-2.5-flash');

        await toolset.processLlmRequest(
          toolContext: _newToolContext(),
          llmRequest: request,
        );

        expect(request.config.systemInstruction, contains('search_skills'));
        expect(
          request.config.systemInstruction,
          contains('discover additional skills from the registry'),
        );
      },
    );

    test(
      'load_skill_resource injects binary content into outgoing llm request',
      () async {
        final SkillToolset toolset = SkillToolset(
          skills: <Skill>[_binarySkill()],
        );
        final BaseTool resourceTool = (await toolset.getTools())[2];
        final LlmRequest request = LlmRequest(
          model: 'gemini-2.5-flash',
          contents: <Content>[
            Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  name: 'load_skill_resource',
                  response: <String, Object?>{
                    'skill_name': 'binary-skill',
                    'file_path': 'assets/document.pdf',
                    'status':
                        'Binary file detected. The content has been injected into the conversation history for you to analyze.',
                  },
                ),
              ],
            ),
          ],
        );

        await resourceTool.processLlmRequest(
          toolContext: _newToolContext(),
          llmRequest: request,
        );

        expect(request.contents, hasLength(2));
        final Content appended = request.contents.last;
        expect(appended.role, 'user');
        expect(appended.parts.first.text, contains('assets/document.pdf'));
        expect(appended.parts.last.inlineData?.mimeType, 'application/pdf');
        expect(appended.parts.last.inlineData?.data, <int>[37, 80, 68, 70]);
      },
    );

    test('system instruction marks load_skill as non-terminal', () {
      final String instruction = defaultSkillSystemInstruction;
      expect(instruction, contains('does NOT complete your turn'));
      expect(instruction, contains('empty response'));
      expect(instruction, contains('run_skill_script'));
    });

    test('prefixed system instruction includes continue after load rule', () async {
      final SkillToolset toolset = SkillToolset(
        skills: <Skill>[_sampleSkill()],
        toolNamePrefix: 'my',
      );
      final LlmRequest request = LlmRequest();
      await toolset.processLlmRequest(
        toolContext: _newToolContext(),
        llmRequest: request,
      );

      final String systemInstruction = request.config.systemInstruction ?? '';
      expect(systemInstruction, contains('does NOT complete your turn'));
      expect(systemInstruction, contains('my_load_skill'));
      expect(systemInstruction, contains('my_run_skill_script'));
    });
  });
}
