import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _DummyTool extends BaseTool {
  _DummyTool({required super.name}) : super(description: 'dummy tool');

  @override
  FunctionDeclaration? getDeclaration() => FunctionDeclaration(name: name);

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    return <String, dynamic>{'result': 'ok'};
  }
}

class _DummyAdvisorModel extends BaseLlm {
  _DummyAdvisorModel() : super(model: 'mock-advisor');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content(
        role: 'model',
        parts: <Part>[Part.text('Here is the advice.')],
      ),
      turnComplete: true,
    );
  }
}

InvocationContext _newInvocationContext({
  required String invocationId,
  BaseAgent? agent,
  Session? session,
}) {
  final BaseAgent resolvedAgent = agent ??
      LlmAgent(name: 'worker', model: 'gemini-2.5-flash');
  final Session resolvedSession = session ??
      Session(id: 's1', appName: 'test', userId: 'u1');
  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: invocationId,
    agent: resolvedAgent,
    session: resolvedSession,
  );
}

void main() {
  group('ModelConsultTool Budget Tests', () {
    test('tracks turn and session budgets correctly', () async {
      final consultTool = ModelConsultTool(
        model: _DummyAdvisorModel(),
        maxConsultationsPerInvocation: 2,
        sessionMaxUses: 3,
      );

      final session = Session(id: 's1', appName: 'test', userId: 'u1');
      final invContext1 = _newInvocationContext(
        invocationId: 'inv-1',
        session: session,
      );
      final toolContext = Context(invContext1);

      expect(consultTool.hasRemainingBudget(toolContext), isTrue);
      expect(consultTool.turnUses(toolContext), 0);
      expect(consultTool.sessionUses(toolContext), 0);

      // Execute first consult
      final res1 = await consultTool.run(
        args: <String, dynamic>{'question': 'How to optimize?'},
        toolContext: toolContext,
      );
      expect(res1, isA<Map<String, dynamic>>());
      expect(consultTool.turnUses(toolContext), 1);
      expect(consultTool.sessionUses(toolContext), 1);
      expect(consultTool.hasRemainingBudget(toolContext), isTrue);

      // Execute second consult in same turn
      await consultTool.run(
        args: <String, dynamic>{'question': 'How to debug?'},
        toolContext: toolContext,
      );
      expect(consultTool.turnUses(toolContext), 2);
      expect(consultTool.sessionUses(toolContext), 2);
      expect(consultTool.hasRemainingBudget(toolContext), isFalse);

      // Third consult in same turn rejected
      final res3 = await consultTool.run(
        args: <String, dynamic>{'question': 'Can I consult again?'},
        toolContext: toolContext,
      ) as Map<String, dynamic>;
      expect(res3['error_code'], 'CONSULTATION_LIMIT_EXCEEDED');

      // Next turn (different invocation ID)
      final invContext2 = _newInvocationContext(
        invocationId: 'inv-2',
        session: session,
      );
      final toolContext2 = Context(invContext2);
      expect(consultTool.turnUses(toolContext2), 0);
      expect(consultTool.sessionUses(toolContext2), 2);
      expect(consultTool.hasRemainingBudget(toolContext2), isTrue);

      // Execute in turn 2
      await consultTool.run(
        args: <String, dynamic>{'question': 'Turn 2 question'},
        toolContext: toolContext2,
      );
      expect(consultTool.sessionUses(toolContext2), 3);
      expect(consultTool.hasRemainingBudget(toolContext2), isFalse);

      // Session budget exhausted
      final res4 = await consultTool.run(
        args: <String, dynamic>{'question': 'Exhausted?'},
        toolContext: toolContext2,
      ) as Map<String, dynamic>;
      expect(res4['error_code'], 'SESSION_CONSULTATION_LIMIT_EXCEEDED');
    });
  });

  group('ForceEscalationPlugin Tests', () {
    test('forceFirstConsult forces consultation on first model turn', () async {
      final plugin = ForceEscalationPlugin(
        toolName: 'consult_model',
        forceFirstConsult: true,
      );

      final consultTool = ModelConsultTool(model: _DummyAdvisorModel());
      final agent = LlmAgent(
        name: 'worker',
        model: 'gemini-2.5-flash',
        tools: <BaseTool>[consultTool],
      );

      final session = Session(id: 's1', appName: 'test', userId: 'u1');
      final invContext = _newInvocationContext(
        invocationId: 'inv-1',
        agent: agent,
        session: session,
      );
      final callbackContext = Context(invContext);

      final request = LlmRequest(
        model: 'gemini-2.5-flash',
        toolsDict: <String, BaseTool>{'consult_model': consultTool},
      );

      await plugin.beforeModelCallback(
        callbackContext: callbackContext,
        llmRequest: request,
      );

      final toolConfig = request.config.toolConfig;
      expect(toolConfig, isNotNull);
      final fcConfig = toolConfig!.functionCallingConfig;
      expect(fcConfig, isNotNull);
      expect(fcConfig!.mode, FunctionCallingConfigMode.any);
      expect(fcConfig.allowedFunctionNames, contains('consult_model'));
    });

    test('requireConsultBefore refuses gated tool before consult occurs',
        () async {
      final plugin = ForceEscalationPlugin(
        toolName: 'consult_model',
        requireConsultBefore: <String>{'dangerous_tool'},
        maxRefusals: 1,
      );

      final session = Session(id: 's1', appName: 'test', userId: 'u1');
      final invContext = _newInvocationContext(
        invocationId: 'inv-1',
        session: session,
      );
      final toolContext = Context(invContext);
      final dangerousTool = _DummyTool(name: 'dangerous_tool');

      // First call should be refused
      final refusal = await plugin.beforeToolCallback(
        tool: dangerousTool,
        toolArgs: <String, dynamic>{'action': 'drop_db'},
        toolContext: toolContext,
      );

      expect(refusal, isNotNull);
      expect(refusal!['status'], consultRequiredStatus);
      expect(refusal['message'], contains('dangerous_tool'));

      // Simulate refused result in afterToolCallback
      await plugin.afterToolCallback(
        tool: dangerousTool,
        toolArgs: <String, dynamic>{'action': 'drop_db'},
        toolContext: toolContext,
        result: refusal,
      );

      // Second call exceeds maxRefusals (1), so it should be allowed (returns null)
      final allowed = await plugin.beforeToolCallback(
        tool: dangerousTool,
        toolArgs: <String, dynamic>{'action': 'drop_db'},
        toolContext: toolContext,
      );
      expect(allowed, isNull);
    });

    test('forceOnRepeat triggers pendingForce on repeated tool calls', () async {
      final plugin = ForceEscalationPlugin(
        toolName: 'consult_model',
        forceFirstConsult: false,
        forceOnRepeat: 2,
      );

      final consultTool = ModelConsultTool(model: _DummyAdvisorModel());
      final repeatTool = _DummyTool(name: 'fetch_data');

      final session = Session(id: 's1', appName: 'test', userId: 'u1');
      final agent = LlmAgent(
        name: 'worker',
        model: 'gemini-2.5-flash',
        tools: <BaseTool>[consultTool, repeatTool],
      );
      final invContext = _newInvocationContext(
        invocationId: 'inv-1',
        agent: agent,
        session: session,
      );
      final toolContext = Context(invContext);
      final callbackContext = toolContext;

      // First model turn (does not force because forceFirstConsult is false)
      final request1 = LlmRequest(
        model: 'gemini-2.5-flash',
        toolsDict: <String, BaseTool>{
          'consult_model': consultTool,
          'fetch_data': repeatTool,
        },
      );
      await plugin.beforeModelCallback(
        callbackContext: callbackContext,
        llmRequest: request1,
      );
      expect(request1.config.toolConfig?.functionCallingConfig?.mode, isNot(FunctionCallingConfigMode.any));

      // Call tool once
      await plugin.afterToolCallback(
        tool: repeatTool,
        toolArgs: <String, dynamic>{'query': 'all'},
        toolContext: toolContext,
        result: <String, dynamic>{'data': 1},
      );

      // Call tool second time with identical args -> triggers repeat threshold
      await plugin.afterToolCallback(
        tool: repeatTool,
        toolArgs: <String, dynamic>{'query': 'all'},
        toolContext: toolContext,
        result: <String, dynamic>{'data': 1},
      );

      // Next model call should be forced to consult
      final request2 = LlmRequest(
        model: 'gemini-2.5-flash',
        toolsDict: <String, BaseTool>{
          'consult_model': consultTool,
          'fetch_data': repeatTool,
        },
      );
      await plugin.beforeModelCallback(
        callbackContext: callbackContext,
        llmRequest: request2,
      );

      expect(
        request2.config.toolConfig?.functionCallingConfig?.mode,
        FunctionCallingConfigMode.any,
      );
      expect(
        request2.config.toolConfig?.functionCallingConfig?.allowedFunctionNames,
        contains('consult_model'),
      );
    });

    test('validates constructor parameters', () {
      expect(
        () => ForceEscalationPlugin(name: ''),
        throwsArgumentError,
      );
      expect(
        () => ForceEscalationPlugin(toolName: ''),
        throwsArgumentError,
      );
      expect(
        () => ForceEscalationPlugin(forceOnRepeat: 0),
        throwsArgumentError,
      );
      expect(
        () => ForceEscalationPlugin(maxForced: -1),
        throwsArgumentError,
      );
      expect(
        () => ForceEscalationPlugin(maxRefusals: -1),
        throwsArgumentError,
      );
      expect(
        () => ForceEscalationPlugin(
          toolName: 'advisor',
          requireConsultBefore: <String>['advisor'],
        ),
        throwsArgumentError,
      );
    });
  });
}
