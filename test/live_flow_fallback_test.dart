import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _EchoLiveModel extends BaseLlm {
  _EchoLiveModel() : super(model: 'echo-live');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String userText = request.contents
        .where((Content content) => content.role == 'user')
        .expand((Content content) => content.parts)
        .where((Part part) => part.text != null && part.text!.isNotEmpty)
        .map((Part part) => part.text!)
        .join(' ')
        .trim();
    yield LlmResponse(content: Content.modelText('live:$userText'));
  }
}

void main() {
  test(
    'LlmAgent live flow consumes queue content and returns model output',
    () async {
      final Agent agent = Agent(
        name: 'root_agent',
        model: _EchoLiveModel(),
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );
      final InMemoryRunner runner = InMemoryRunner(agent: agent);
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'u1',
        sessionId: 's_live_flow',
      );

      final LiveRequestQueue queue = LiveRequestQueue()
        ..sendContent(Content.userText('hello'))
        ..close();

      final List<Event> events = await runner
          .runLive(liveRequestQueue: queue, session: session)
          .toList();
      expect(
        events.any(
          (Event event) =>
              event.content?.parts.first.text?.contains('live:') == true,
        ),
        isTrue,
      );
    },
  );
}
