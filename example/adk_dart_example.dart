import 'package:adk_dart/adk_dart.dart';

class EchoModel extends BaseLlm {
  EchoModel() : super(model: 'echo');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String lastUserText = request.contents.isEmpty
        ? ''
        : request.contents.last.parts
              .where((Part part) => part.text != null)
              .map((Part part) => part.text!)
              .join(' ');

    yield LlmResponse(content: Content.modelText('echo: $lastUserText'));
  }
}

Future<void> main() async {
  final Agent agent = Agent(name: 'echo_agent', model: EchoModel());
  final InMemoryRunner runner = InMemoryRunner(agent: agent);

  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'example_user',
    sessionId: 'example_session',
  );

  await for (final Event event in runner.runAsync(
    userId: 'example_user',
    sessionId: session.id,
    newMessage: Content.userText('hello adk_dart'),
  )) {
    final String text =
        event.content?.parts
            .where((Part part) => part.text != null)
            .map((Part part) => part.text!)
            .join(' ') ??
        '';
    print('[${event.author}] $text');
  }
}
