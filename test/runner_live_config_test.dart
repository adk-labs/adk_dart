import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _LiveEchoAgent extends BaseAgent {
  _LiveEchoAgent({required super.name, super.subAgents});

  RunConfig? seenRunConfig;

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {}

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    seenRunConfig = context.runConfig;
    yield Event(
      invocationId: context.invocationId,
      author: name,
      branch: context.branch,
      content: Content.modelText('live ok'),
    );
  }
}

void main() {
  test('RunConfig defaults maxLlmCalls to a bounded value', () {
    expect(RunConfig().maxLlmCalls, 500);
  });

  test('RunConfig allows non-positive maxLlmCalls for unbounded runs', () {
    expect(RunConfig(maxLlmCalls: 0).maxLlmCalls, 0);
    expect(RunConfig(maxLlmCalls: -1).maxLlmCalls, -1);
  });

  test('RunConfig rejects Python sys.maxsize for maxLlmCalls', () {
    expect(
      () => RunConfig(maxLlmCalls: 9223372036854775807),
      throwsArgumentError,
    );
    expect(
      () => RunConfig().copyWith(maxLlmCalls: 9223372036854775807),
      throwsArgumentError,
    );
  });

  test(
    'runLive applies default audio modality and transcription placeholders',
    () async {
      final _LiveEchoAgent subAgent = _LiveEchoAgent(name: 'sub_agent');
      final _LiveEchoAgent root = _LiveEchoAgent(
        name: 'root_agent',
        subAgents: <BaseAgent>[subAgent],
      );

      final InMemoryRunner runner = InMemoryRunner(agent: root);
      final RunConfig config = RunConfig();
      final Session session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: 'u1',
        sessionId: 's_live_defaults',
      );

      final List<Event> events = await runner
          .runLive(
            liveRequestQueue: LiveRequestQueue(),
            session: session,
            runConfig: config,
          )
          .toList();

      expect(events, hasLength(1));
      expect(events.first.content?.parts.first.text, 'live ok');
      expect(config.responseModalities, <String>['AUDIO']);
      expect(config.outputAudioTranscription, isNotNull);
      expect(config.inputAudioTranscription, isNotNull);
    },
  );
}
