import 'dart:async';

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

class _InlineMediaLiveAgent extends BaseAgent {
  _InlineMediaLiveAgent({required super.name, required this.mimeType});

  final String mimeType;

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {}

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      branch: context.branch,
      content: Content(
        role: 'model',
        parts: <Part>[
          Part.fromInlineData(mimeType: mimeType, data: <int>[1, 0, 2, 0]),
        ],
      ),
    );
  }
}

class _FlushTrackingSessionService extends InMemorySessionService {
  int flushCalls = 0;

  @override
  Future<void> flush() async {
    flushCalls += 1;
    await super.flush();
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

  test('RunConfig warns when maxLlmCalls is non-positive', () {
    final List<String> printed = <String>[];
    runZoned(
      () {
        RunConfig(maxLlmCalls: 0);
        RunConfig(maxLlmCalls: -1);
      },
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          printed.add(line);
        },
      ),
    );

    final int warningCount = printed
        .where(
          (String line) =>
              line.contains('maxLlmCalls is less than or equal to 0'),
        )
        .length;
    expect(warningCount, 2);
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

  for (final String mimeType in <String>[
    'audio/pcm;rate=24000',
    'video/mp4',
    'image/png',
  ]) {
    test(
      'runLive does not persist inline $mimeType events to session',
      () async {
        final _InlineMediaLiveAgent root = _InlineMediaLiveAgent(
          name: 'root_agent',
          mimeType: mimeType,
        );
        final InMemoryRunner runner = InMemoryRunner(agent: root);
        final Session session = await runner.sessionService.createSession(
          appName: runner.appName,
          userId: 'u1',
          sessionId: 's_live_inline_${mimeType.split('/').first}',
        );

        final List<Event> events = await runner
            .runLive(
              liveRequestQueue: LiveRequestQueue()..close(),
              session: session,
            )
            .toList();
        expect(events, hasLength(1));
        expect(events.first.content?.parts.first.inlineData, isNotNull);

        final Session? updated = await runner.sessionService.getSession(
          appName: runner.appName,
          userId: session.userId,
          sessionId: session.id,
        );
        expect(updated, isNotNull);
        expect(updated!.events, isEmpty);
      },
    );
  }

  test('close flushes the session service', () async {
    final _FlushTrackingSessionService sessionService =
        _FlushTrackingSessionService();
    final Runner runner = Runner(
      appName: 'app',
      agent: _LiveEchoAgent(name: 'root_agent'),
      sessionService: sessionService,
      artifactService: InMemoryArtifactService(),
    );

    await runner.close();

    expect(sessionService.flushCalls, 1);
  });
}
