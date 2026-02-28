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

class _ResumptionMetadataModel extends BaseLlm {
  _ResumptionMetadataModel() : super(model: 'resumption-live');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content.modelText('ok'),
      customMetadata: <String, dynamic>{
        'live_session_resumption_update': <String, Object?>{
          'new_handle': 'next-live-handle',
        },
      },
    );
  }
}

Future<InvocationContext> _newInvocationContext({
  required LlmAgent agent,
  required String invocationId,
  required LiveRequestQueue liveRequestQueue,
}) async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'app',
    userId: 'u1',
    sessionId: 's_$invocationId',
  );

  return InvocationContext(
    sessionService: sessionService,
    invocationId: invocationId,
    agent: agent,
    session: session,
    liveRequestQueue: liveRequestQueue,
  );
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

  test(
    'live fallback fans out live requests to active streaming tools',
    () async {
      final LlmAgent agent = LlmAgent(name: 'agent', model: _EchoLiveModel());
      final LiveRequestQueue rootQueue = LiveRequestQueue()
        ..sendContent(Content.userText('fanout'))
        ..close();
      final LiveRequestQueue mirroredQueue = LiveRequestQueue();

      final InvocationContext context = await _newInvocationContext(
        agent: agent,
        invocationId: 'inv_fallback_fanout',
        liveRequestQueue: rootQueue,
      );
      context.activeStreamingTools = <String, ActiveStreamingTool>{
        'tool_1': ActiveStreamingTool(stream: mirroredQueue),
      };

      final List<Event> events = await BaseLlmFlow().runLive(context).toList();
      expect(events, isNotEmpty);

      final LiveRequest mirroredContent = await mirroredQueue.get();
      final LiveRequest mirroredClose = await mirroredQueue.get();
      expect(mirroredContent.content?.parts.single.text, 'fanout');
      expect(mirroredClose.close, isTrue);
    },
  );

  test(
    'live fallback updates invocation resumption handle from model metadata',
    () async {
      final LlmAgent agent = LlmAgent(
        name: 'agent',
        model: _ResumptionMetadataModel(),
      );
      final LiveRequestQueue queue = LiveRequestQueue()
        ..sendContent(Content.userText('hello'))
        ..close();
      final InvocationContext context =
          await _newInvocationContext(
              agent: agent,
              invocationId: 'inv_fallback_resumption',
              liveRequestQueue: queue,
            )
            ..liveSessionResumptionHandle = 'old-handle';

      final List<Event> events = await BaseLlmFlow().runLive(context).toList();
      expect(events, isNotEmpty);
      expect(context.liveSessionResumptionHandle, 'next-live-handle');
    },
  );
}
