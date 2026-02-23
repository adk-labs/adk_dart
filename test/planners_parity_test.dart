import 'package:adk_dart/adk_dart.dart';
import 'package:adk_dart/src/flows/llm_flows/nl_planning.dart';
import 'package:test/test.dart';

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

InvocationContext _newInvocationContext({Object? planner}) {
  final LlmAgent agent = LlmAgent(
    name: 'root_agent',
    model: _NoopModel(),
    planner: planner,
    disallowTransferToParent: true,
    disallowTransferToPeers: true,
  );

  return InvocationContext(
    sessionService: InMemorySessionService(),
    invocationId: 'inv_1',
    agent: agent,
    session: Session(id: 's1', appName: 'app', userId: 'u1'),
  );
}

class _StateWritingPlanner extends BasePlanner {
  @override
  String? buildPlanningInstruction(
    ReadonlyContext readonlyContext,
    LlmRequest llmRequest,
  ) {
    return null;
  }

  @override
  List<Part>? processPlanningResponse(
    CallbackContext callbackContext,
    List<Part> responseParts,
  ) {
    callbackContext.state['planner_test'] = 'ok';
    return <Part>[Part.text('processed')];
  }
}

void main() {
  group('PlanReActPlanner', () {
    test('builds prompt containing required tags', () {
      final PlanReActPlanner planner = PlanReActPlanner();
      final String instruction = planner.buildPlanningInstruction(
        ReadonlyContext(_newInvocationContext(planner: planner)),
        LlmRequest(),
      );

      expect(instruction, contains(planningTag));
      expect(instruction, contains(replanningTag));
      expect(instruction, contains(reasoningTag));
      expect(instruction, contains(actionTag));
      expect(instruction, contains(finalAnswerTag));
      expect(instruction, contains('VERY IMPORTANT instruction'));
    });

    test(
      'processes plan/reasoning/final-answer and preserves function calls',
      () {
        final PlanReActPlanner planner = PlanReActPlanner();
        final List<Part>? processed = planner.processPlanningResponse(
          Context(_newInvocationContext(planner: planner)),
          <Part>[
            Part.text('$planningTag\n1. Search docs'),
            Part.text('$reasoningTag Check evidence $finalAnswerTag done'),
            Part.fromFunctionCall(name: 'tool_a', args: <String, dynamic>{}),
            Part.fromFunctionCall(name: 'tool_b', args: <String, dynamic>{}),
            Part.text('ignored trailing text'),
          ],
        );

        expect(processed, isNotNull);
        expect(processed!, hasLength(5));

        expect(processed[0].text, contains(planningTag));
        expect(processed[0].thought, isTrue);

        expect(processed[1].text, contains(finalAnswerTag));
        expect(processed[1].thought, isTrue);

        expect(processed[2].text, ' done');
        expect(processed[2].thought, isFalse);

        expect(processed[3].functionCall?.name, 'tool_a');
        expect(processed[4].functionCall?.name, 'tool_b');
      },
    );

    test('ignores empty-name function calls', () {
      final PlanReActPlanner planner = PlanReActPlanner();
      final List<Part>? processed = planner.processPlanningResponse(
        Context(_newInvocationContext(planner: planner)),
        <Part>[
          Part.fromFunctionCall(name: '', args: <String, dynamic>{}),
          Part.text('plain response'),
        ],
      );

      expect(processed, isNotNull);
      expect(processed, hasLength(1));
      expect(processed!.first.text, 'plain response');
    });
  });

  group('NL planning processors', () {
    test(
      'request processor applies thinking config for BuiltInPlanner',
      () async {
        final BuiltInPlanner planner = BuiltInPlanner(
          thinkingConfig: <String, Object?>{'budget': 128},
        );
        final InvocationContext context = _newInvocationContext(
          planner: planner,
        );
        final LlmRequest request = LlmRequest();

        final List<Event> emitted = await NlPlanningRequestProcessor()
            .runAsync(context, request)
            .toList();

        expect(emitted, isEmpty);
        expect(request.config.thinkingConfig, <String, Object?>{'budget': 128});
      },
    );

    test('built-in planner leaves request contents untouched', () async {
      final BuiltInPlanner planner = BuiltInPlanner(
        thinkingConfig: <String, Object?>{'budget': 64},
      );
      final InvocationContext context = _newInvocationContext(planner: planner);
      final LlmRequest request = LlmRequest(
        contents: <Content>[
          Content(role: 'user', parts: <Part>[Part.text('Hello')]),
          Content(
            role: 'model',
            parts: <Part>[
              Part.text('thinking...', thought: true),
              Part.text('response'),
            ],
          ),
          Content(role: 'user', parts: <Part>[Part.text('Follow up')]),
        ],
      );

      final List<Part> originalParts = request.contents
          .expand((Content content) => content.parts)
          .map((Part part) => part.copyWith())
          .toList(growable: false);

      await NlPlanningRequestProcessor().runAsync(context, request).toList();

      final List<Part> updatedParts = request.contents
          .expand((Content content) => content.parts)
          .toList(growable: false);
      expect(updatedParts, hasLength(originalParts.length));
      for (int i = 0; i < updatedParts.length; i += 1) {
        expect(updatedParts[i].text, originalParts[i].text);
        expect(updatedParts[i].thought, originalParts[i].thought);
      }
    });

    test(
      'request processor defaults to PlanReAct for non-BasePlanner planner',
      () async {
        final InvocationContext context = _newInvocationContext(
          planner: 'plan_react_default',
        );
        final LlmRequest request = LlmRequest(
          contents: <Content>[
            Content(role: 'user', parts: <Part>[Part.text('q', thought: true)]),
          ],
        );

        final List<Event> emitted = await NlPlanningRequestProcessor()
            .runAsync(context, request)
            .toList();

        expect(emitted, isEmpty);
        expect(request.config.systemInstruction, isNotNull);
        expect(request.config.systemInstruction, contains(planningTag));
        expect(request.contents.first.parts.first.thought, isFalse);
      },
    );

    test(
      'response processor postprocesses parts and emits state delta event',
      () async {
        final InvocationContext context = _newInvocationContext(
          planner: _StateWritingPlanner(),
        );
        final LlmResponse response = LlmResponse(
          content: Content(role: 'model', parts: <Part>[Part.text('raw')]),
        );

        final List<Event> emitted = await NlPlanningResponseProcessor()
            .runAsync(context, response)
            .toList();

        expect(response.content?.parts, hasLength(1));
        expect(response.content?.parts.first.text, 'processed');
        expect(emitted, hasLength(1));
        expect(emitted.first.actions.stateDelta, isNotEmpty);
      },
    );
  });

  test('LlmAgent llmFlow includes NL planning processors', () {
    final LlmAgent agent = LlmAgent(
      name: 'root_agent',
      model: _NoopModel(),
      planner: PlanReActPlanner(),
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
    );
    final BaseLlmFlow flow = agent.llmFlow;

    expect(
      flow.requestProcessors.any(
        (BaseLlmRequestProcessor processor) =>
            processor is NlPlanningRequestProcessor,
      ),
      isTrue,
    );
    expect(
      flow.responseProcessors.any(
        (BaseLlmResponseProcessor processor) =>
            processor is NlPlanningResponseProcessor,
      ),
      isTrue,
    );
  });
}
