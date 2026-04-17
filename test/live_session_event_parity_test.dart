import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _LiveSessionIdModel extends BaseLlm {
  _LiveSessionIdModel() : super(model: 'live-session-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content.modelText('live response'),
      liveSessionId: 'live_session_1',
    );
  }
}

void main() {
  test(
    'llm flow propagates liveSessionId from model response to event',
    () async {
      final Agent agent = Agent(
        name: 'root_agent',
        model: _LiveSessionIdModel(),
        instruction: 'Respond to the user.',
      );
      final InvocationContext context = InvocationContext(
        sessionService: InMemorySessionService(),
        invocationId: 'inv_live_session',
        agent: agent,
        session: Session(
          id: 'session_live_session',
          appName: 'app',
          userId: 'u1',
          events: <Event>[
            Event(
              invocationId: 'inv_live_session',
              author: 'user',
              content: Content.userText('hello'),
            ),
          ],
        ),
      );

      final List<Event> events = await agent.runAsync(context).toList();
      final Event modelEvent = events.firstWhere(
        (Event event) => event.author == 'root_agent' && event.content != null,
      );

      expect(modelEvent.liveSessionId, 'live_session_1');
    },
  );
}
