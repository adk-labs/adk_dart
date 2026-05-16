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

Future<List<Event>> _runOnce(LlmAgent agent) async {
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
