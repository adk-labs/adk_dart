import 'package:adk/adk.dart';

class EchoModel extends BaseLlm {
  EchoModel() : super(model: 'echo');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content.modelText('hello from adk package'),
    );
  }
}

Future<void> main() async {
  final Agent agent = Agent(name: 'root_agent', model: EchoModel());
  final InMemoryRunner runner = InMemoryRunner(agent: agent);
  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'user_1',
    sessionId: 'session_1',
  );

  final List<Event> events = await runner
      .runAsync(
        userId: 'user_1',
        sessionId: session.id,
        newMessage: Content.userText('hi'),
      )
      .toList();

  if (events.isNotEmpty) {
    print(events.last.content?.parts.first.text);
  }
}
