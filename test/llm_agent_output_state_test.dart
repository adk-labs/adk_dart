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
  });
}
