import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _StaticTextModel extends BaseLlm {
  _StaticTextModel(this.text) : super(model: 'static-text');

  final String text;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content(role: 'model', parts: <Part>[Part.text(text)]),
    );
  }
}

class _ToolCallModel extends BaseLlm {
  _ToolCallModel() : super(model: 'tool-call');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content(
        role: 'model',
        parts: <Part>[
          Part.fromFunctionCall(
            name: 'lookup',
            args: <String, dynamic>{'query': 'x'},
          ),
        ],
      ),
    );
  }
}

class _StaticFlow extends BaseLlmFlow {
  _StaticFlow(this.text);

  final String text;

  @override
  Stream<Event> runAsync(InvocationContext context) async* {
    yield _event(context);
  }

  @override
  Stream<Event> runLive(InvocationContext context) async* {
    yield _event(context);
  }

  Event _event(InvocationContext context) {
    return Event(
      invocationId: context.invocationId,
      author: context.agent.name,
      branch: context.branch,
      content: Content.modelText(text),
    );
  }
}

class _FlowBackedLlmAgent extends LlmAgent {
  _FlowBackedLlmAgent({
    required super.name,
    required String text,
    super.outputKey,
    super.beforeAgentCallback,
    super.afterAgentCallback,
  }) : _flow = _StaticFlow(text);

  final BaseLlmFlow _flow;

  @override
  BaseLlmFlow get llmFlow => _flow;
}

class _StateRecordingPlugin extends BasePlugin {
  _StateRecordingPlugin() : super(name: 'state_recording');

  Object? finalAnswerInAfterRun;

  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    finalAnswerInAfterRun = invocationContext.session.state['final_answer'];
  }
}

Future<List<Event>> _runOnce(BaseAgent agent) async {
  final InMemoryRunner runner = InMemoryRunner(agent: agent);
  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'u1',
    sessionId: 's_output_state',
  );
  return runner
      .runAsync(
        userId: 'u1',
        sessionId: session.id,
        newMessage: Content.userText('hello'),
      )
      .toList();
}

void main() {
  group('LlmAgent output state persistence', () {
    test(
      'parses structured JSON output into state delta when outputSchema is set',
      () async {
        final LlmAgent agent = LlmAgent(
          name: 'root_agent',
          model: _StaticTextModel('{"answer":"done"}'),
          outputSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'answer': <String, Object?>{'type': 'string'},
            },
          },
          outputKey: 'final_answer',
          disallowTransferToParent: true,
          disallowTransferToPeers: true,
        );

        final List<Event> events = await _runOnce(agent);
        final Event eventWithState = events.firstWhere(
          (Event event) => event.actions.stateDelta.containsKey('final_answer'),
        );

        expect(eventWithState.actions.stateDelta['final_answer'], isA<Map>());
        expect(
          (eventWithState.actions.stateDelta['final_answer'] as Map)['answer'],
          'done',
        );
      },
    );

    test(
      'runner updates context session state before after-run callbacks',
      () async {
        final _StateRecordingPlugin plugin = _StateRecordingPlugin();
        final LlmAgent agent = LlmAgent(
          name: 'root_agent',
          model: _StaticTextModel('visible'),
          outputKey: 'final_answer',
          disallowTransferToParent: true,
          disallowTransferToPeers: true,
        );
        final InMemoryRunner runner = InMemoryRunner(
          agent: agent,
          plugins: <BasePlugin>[plugin],
        );
        final Session session = await runner.sessionService.createSession(
          appName: runner.appName,
          userId: 'u1',
          sessionId: 's_output_key_visibility',
        );

        await runner
            .runAsync(
              userId: 'u1',
              sessionId: session.id,
              newMessage: Content.userText('hello'),
            )
            .toList();

        expect(plugin.finalAnswerInAfterRun, 'visible');
        final Session? stored = await runner.sessionService.getSession(
          appName: runner.appName,
          userId: 'u1',
          sessionId: session.id,
        );
        expect(stored?.state['final_answer'], 'visible');
      },
    );

    test('outputKey state is visible inside after-agent callback', () async {
      Object? callbackStateValue;
      Object? callbackSessionStateValue;
      final LlmAgent agent = _FlowBackedLlmAgent(
        name: 'root_agent',
        text: 'visible',
        outputKey: 'final_answer',
        afterAgentCallback: (CallbackContext callbackContext) {
          callbackStateValue = callbackContext.state['final_answer'];
          callbackSessionStateValue =
              callbackContext.session.state['final_answer'];
          return null;
        },
      );

      await _runOnce(agent);

      expect(callbackStateValue, 'visible');
      expect(callbackSessionStateValue, 'visible');
    });

    test(
      'outputKey state is visible inside after-agent callback in live run',
      () async {
        Object? callbackStateValue;
        Object? callbackSessionStateValue;
        final LlmAgent agent = _FlowBackedLlmAgent(
          name: 'root_agent',
          text: 'live visible',
          outputKey: 'final_answer',
          afterAgentCallback: (CallbackContext callbackContext) {
            callbackStateValue = callbackContext.state['final_answer'];
            callbackSessionStateValue =
                callbackContext.session.state['final_answer'];
            return null;
          },
        );
        final InMemoryRunner runner = InMemoryRunner(agent: agent);
        final Session session = await runner.sessionService.createSession(
          appName: runner.appName,
          userId: 'u1',
          sessionId: 's_output_key_live_visibility',
        );

        await runner
            .runLive(
              liveRequestQueue: LiveRequestQueue()..close(),
              session: session,
            )
            .toList();

        expect(callbackStateValue, 'live visible');
        expect(callbackSessionStateValue, 'live visible');
      },
    );

    test(
      'outputKey state is visible to next sequential agent before callback',
      () async {
        Object? callbackSessionStateValue;
        final LlmAgent first = _FlowBackedLlmAgent(
          name: 'first_agent',
          text: 'from first',
          outputKey: 'final_answer',
        );
        final LlmAgent second = _FlowBackedLlmAgent(
          name: 'second_agent',
          text: 'from second',
          beforeAgentCallback: (CallbackContext callbackContext) {
            callbackSessionStateValue =
                callbackContext.session.state['final_answer'];
            return null;
          },
        );
        final SequentialAgent agent = SequentialAgent(
          name: 'seq_agent',
          subAgents: <BaseAgent>[first, second],
        );

        await _runOnce(agent);

        expect(callbackSessionStateValue, 'from first');
      },
    );

    test('skips outputSchema parsing for empty final chunks', () async {
      final LlmAgent agent = LlmAgent(
        name: 'root_agent',
        model: _StaticTextModel('   '),
        outputSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'answer': <String, Object?>{'type': 'string'},
          },
        },
        outputKey: 'final_answer',
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );

      final List<Event> events = await _runOnce(agent);
      expect(
        events
            .where(
              (Event event) =>
                  event.actions.stateDelta.containsKey('final_answer'),
            )
            .toList(),
        isEmpty,
      );
    });

    test(
      'does not overwrite outputKey for function-response-only final event',
      () async {
        final LlmAgent agent = LlmAgent(
          name: 'root_agent',
          model: _ToolCallModel(),
          outputKey: 'final_answer',
          tools: <Object>[
            FunctionTool(
              name: 'lookup',
              description: 'Looks up a value.',
              func: ({required String query}) => <String, Object?>{
                'query': query,
                'value': 1,
              },
            ),
          ],
          afterToolCallback:
              (
                BaseTool tool,
                Map<String, dynamic> args,
                ToolContext toolContext,
                Map<String, dynamic> toolResponse,
              ) {
                toolContext.actions.skipSummarization = true;
                toolContext.actions.stateDelta['tool_value'] =
                    toolResponse['value'];
                return null;
              },
        );

        final List<Event> events = await _runOnce(agent);
        final Event functionResponseEvent = events.firstWhere(
          (Event event) => event.getFunctionResponses().isNotEmpty,
        );

        expect(functionResponseEvent.actions.skipSummarization, isTrue);
        expect(functionResponseEvent.actions.stateDelta['tool_value'], 1);
        expect(
          functionResponseEvent.actions.stateDelta.containsKey('final_answer'),
          isFalse,
        );
      },
    );
  });
}
