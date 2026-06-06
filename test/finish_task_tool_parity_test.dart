import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('FinishTaskTool parity', () {
    test('exposes default finish_task declaration', () {
      final LlmAgent agent = LlmAgent(name: 'task_agent', mode: 'task');
      final FinishTaskTool tool = agent.tools
          .whereType<FinishTaskTool>()
          .single;

      expect(tool.name, finishTaskToolName);
      expect(
        tool.description,
        contains('Signal that this agent has completed'),
      );
      expect(tool.description, isNot(contains('output data')));

      final FunctionDeclaration declaration = tool.getDeclaration();
      expect(declaration.name, finishTaskToolName);
      expect(declaration.parameters['type'], 'object');
      expect(declaration.parameters['required'], <String>['result']);
      final Map<String, Object?> properties =
          declaration.parameters['properties'] as Map<String, Object?>;
      expect(properties['result'], isA<Map<String, Object?>>());
    });

    test('uses object output schema directly', () {
      final FinishTaskTool tool = FinishTaskTool.fromSchema(
        taskAgentName: 'task_agent',
        outputSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'result': <String, Object?>{'type': 'string'},
            'count': <String, Object?>{'type': 'integer'},
          },
          'required': <String>['result', 'count'],
          'additionalProperties': false,
        },
      );

      expect(tool.description, contains('output data'));
      final FunctionDeclaration declaration = tool.getDeclaration();
      final Map<String, Object?> properties =
          declaration.parameters['properties'] as Map<String, Object?>;
      expect(properties.keys, containsAll(<String>['result', 'count']));
      expect(declaration.parameters['required'], <String>['result', 'count']);
    });

    test('wraps primitive output schema in result property', () {
      final FinishTaskTool tool = FinishTaskTool.fromSchema(
        taskAgentName: 'task_agent',
        outputSchema: String,
      );

      final FunctionDeclaration declaration = tool.getDeclaration();
      expect(declaration.parameters['type'], 'object');
      expect(declaration.parameters['required'], <String>['result']);
      final Map<String, Object?> properties =
          declaration.parameters['properties'] as Map<String, Object?>;
      expect((properties['result'] as Map<String, Object?>)['type'], 'string');
    });

    test('processLlmRequest appends tool and finish instruction', () async {
      final FinishTaskTool tool = FinishTaskTool.fromSchema(
        taskAgentName: 'task_agent',
      );
      final LlmRequest request = LlmRequest(model: 'gemini-2.5-flash');
      await tool.processLlmRequest(
        toolContext: _newToolContext(),
        llmRequest: request,
      );

      expect(request.toolsDict[finishTaskToolName], same(tool));
      expect(
        request.config.tools!.single.functionDeclarations.single.name,
        finishTaskToolName,
      );
      expect(
        request.config.systemInstruction,
        contains('Do NOT call `finish_task` prematurely'),
      );
      expect(
        request.config.systemInstruction,
        contains('call `finish_task` by itself'),
      );
    });

    test('run validates object schema and returns confirmation', () async {
      final FinishTaskTool tool = FinishTaskTool.fromSchema(
        taskAgentName: 'task_agent',
        outputSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'result': <String, Object?>{'type': 'string'},
            'count': <String, Object?>{'type': 'integer'},
          },
          'required': <String>['result', 'count'],
          'additionalProperties': false,
        },
      );

      final Object? result = await tool.run(
        args: <String, dynamic>{'result': 'done', 'count': 1},
        toolContext: _newToolContext(),
      );

      expect(result, finishTaskSuccessResult);
    });

    test('run returns validation error for missing or wrong fields', () async {
      final FinishTaskTool tool = FinishTaskTool.fromSchema(
        taskAgentName: 'task_agent',
        outputSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'result': <String, Object?>{'type': 'string'},
            'count': <String, Object?>{'type': 'integer'},
          },
          'required': <String>['result', 'count'],
        },
      );

      final Object? missing = await tool.run(
        args: <String, dynamic>{'result': 'done'},
        toolContext: _newToolContext(),
      );
      expect(missing, isA<Map>());
      final Map missingError = missing! as Map;
      expect(missingError['error'], contains('finish_task'));
      expect(missingError['error'], contains('count'));

      final Object? wrongType = await tool.run(
        args: <String, dynamic>{'result': 'done', 'count': 'one'},
        toolContext: _newToolContext(),
      );
      expect(wrongType, isA<Map>());
      expect((wrongType! as Map)['error'], contains('expected integer'));
    });

    test('run validates wrapped primitive schema', () async {
      final FinishTaskTool tool = FinishTaskTool.fromSchema(
        taskAgentName: 'task_agent',
        outputSchema: int,
      );

      expect(
        await tool.run(
          args: <String, dynamic>{'result': 42},
          toolContext: _newToolContext(),
        ),
        finishTaskSuccessResult,
      );

      final Object? error = await tool.run(
        args: <String, dynamic>{'result': '42'},
        toolContext: _newToolContext(),
      );
      expect(error, isA<Map>());
      expect((error! as Map)['error'], contains('expected integer'));
    });

    test('LlmAgent task mode auto-installs finish_task once', () {
      final FinishTaskTool existing = FinishTaskTool.fromSchema(
        taskAgentName: 'task_agent',
      );
      final LlmAgent agent = LlmAgent(
        name: 'task_agent',
        mode: 'task',
        tools: <Object>[existing],
      );

      expect(agent.mode, 'task');
      expect(agent.tools.whereType<FinishTaskTool>(), hasLength(1));
      expect(agent.tools.whereType<FinishTaskTool>().single, same(existing));
    });

    test('LlmAgent clone preserves mode without duplicating finish_task', () {
      final LlmAgent agent = LlmAgent(name: 'task_agent', mode: 'task');

      final LlmAgent cloned = agent.clone(
        update: <String, Object?>{'name': 'cloned_task'},
      );

      expect(cloned.mode, 'task');
      expect(cloned.tools.whereType<FinishTaskTool>(), hasLength(1));
      expect(
        cloned.tools.whereType<FinishTaskTool>().single.taskAgentName,
        'cloned_task',
      );
    });

    test('LlmAgentConfig parses and serializes mode', () {
      final LlmAgentConfig config = LlmAgentConfig.fromJson(<String, Object?>{
        'name': 'task_agent',
        'instruction': 'Complete the task.',
        'mode': 'task',
      });

      expect(config.mode, 'task');
      expect(config.toJson()['mode'], 'task');
      expect(
        () => LlmAgentConfig.fromJson(<String, Object?>{
          'name': 'bad_agent',
          'instruction': 'x',
          'mode': 'invalid',
        }),
        throwsArgumentError,
      );
    });

    test('TaskRequest and TaskResult use Python-compatible JSON keys', () {
      final TaskRequest request = TaskRequest.fromJson(<String, Object?>{
        'agentName': 'worker',
        'input': <String, Object?>{'goal': 'ship'},
      });
      expect(request.toJson(), <String, Object?>{
        'agent_name': 'worker',
        'input': <String, Object?>{'goal': 'ship'},
      });

      final TaskResult result = TaskResult(
        output: <String, Object?>{'ok': true},
      );
      expect(result.toJson(), <String, Object?>{
        'output': <String, Object?>{'ok': true},
      });
    });
  });
}

Context _newToolContext() {
  return Context(
    InvocationContext(
      sessionService: InMemorySessionService(),
      invocationId: 'inv_finish_task',
      agent: LlmAgent(name: 'root'),
      session: Session(id: 's_finish_task', appName: 'app', userId: 'user'),
    ),
  );
}
