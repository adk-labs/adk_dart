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
    ),
    instructions: 'Follow these steps carefully.',
    resources: Resources(
      references: <String, String>{'guide.md': 'reference doc'},
      assets: <String, String>{'template.txt': 'asset template'},
      scripts: <String, Script>{'setup.sh': Script(src: 'echo setup')},
    ),
  );
}

class _FakeCodeExecutor extends BaseCodeExecutor {
  _FakeCodeExecutor(this.result);

  final CodeExecutionResult result;
  String? lastCode;

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
    return result;
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
        args: <String, dynamic>{'name': 'my-skill'},
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
      expect(missingPayload['error_code'], 'MISSING_SKILL_NAME');

      final Object? notFound = await loadTool.run(
        args: <String, dynamic>{'name': 'unknown-skill'},
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
            'path': 'references/guide.md',
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
            'path': 'assets/template.txt',
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
            'path': 'scripts/setup.sh',
          },
          toolContext: _newToolContext(),
        );
        expect(
          Map<String, Object?>.from(script! as Map)['content'],
          'echo setup',
        );
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
          'path': 'other/file.txt',
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
          'path': 'references/missing.md',
        },
        toolContext: _newToolContext(),
      );
      expect(
        Map<String, Object?>.from(missingResource! as Map)['error_code'],
        'RESOURCE_NOT_FOUND',
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
            'script_path': 'scripts/setup.sh',
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
          'script_path': 'scripts/setup.sh',
          'args': <String, Object?>{'name': 'dart'},
        },
        toolContext: _newToolContext(),
      );
      final Map<String, Object?> payload = Map<String, Object?>.from(
        result! as Map,
      );
      expect(payload['status'], 'success');
      expect(payload['stdout'], 'done');
      expect(fakeExecutor.lastCode, contains('scripts/setup.sh'));
      expect(fakeExecutor.lastCode, contains('--name'));
      expect(fakeExecutor.lastCode, contains('dart'));
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
        expect(instruction, contains('<available_skills>'));
        expect(instruction, contains('my-skill'));
      },
    );
  });
}
