import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _RecordingSessionService extends InMemorySessionService {
  final List<GetSessionConfig?> capturedConfigs = <GetSessionConfig?>[];

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) {
    capturedConfigs.add(config);
    return super.getSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      config: config,
    );
  }
}

class _RunnerTestAgent extends BaseAgent {
  _RunnerTestAgent({required super.name});

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      branch: context.branch,
      content: Content.modelText('async ok'),
    );
  }

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    yield Event(
      invocationId: context.invocationId,
      author: name,
      branch: context.branch,
      content: Content.modelText('live ok'),
    );
  }
}

void main() {
  group('Runner getSessionConfig parity', () {
    test('runAsync forwards getSessionConfig to session service', () async {
      final _RecordingSessionService sessionService =
          _RecordingSessionService();
      final Runner runner = Runner(
        appName: 'app',
        agent: _RunnerTestAgent(name: 'agent'),
        sessionService: sessionService,
      );
      await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
      );

      final GetSessionConfig config = GetSessionConfig(numRecentEvents: 3);
      final List<Event> events = await runner
          .runAsync(
            userId: 'u1',
            sessionId: 's1',
            newMessage: Content.userText('hello'),
            runConfig: RunConfig(getSessionConfig: config),
          )
          .toList();

      expect(events, isNotEmpty);
      expect(sessionService.capturedConfigs.last?.numRecentEvents, 3);
    });

    test('runLive forwards getSessionConfig to session service', () async {
      final _RecordingSessionService sessionService =
          _RecordingSessionService();
      final Runner runner = Runner(
        appName: 'app',
        agent: _RunnerTestAgent(name: 'agent'),
        sessionService: sessionService,
      );
      await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's_live',
      );

      final GetSessionConfig config = GetSessionConfig(numRecentEvents: 5);
      final List<Event> events = await runner
          .runLive(
            userId: 'u1',
            sessionId: 's_live',
            liveRequestQueue: LiveRequestQueue()..close(),
            runConfig: RunConfig(getSessionConfig: config),
          )
          .toList();

      expect(events, isNotEmpty);
      expect(sessionService.capturedConfigs.last?.numRecentEvents, 5);
    });

    test('rewindAsync forwards getSessionConfig to session service', () async {
      final _RecordingSessionService sessionService =
          _RecordingSessionService();
      final Runner runner = Runner(
        appName: 'app',
        agent: _RunnerTestAgent(name: 'agent'),
        sessionService: sessionService,
        autoCreateSession: true,
      );

      final RunConfig runConfig = RunConfig(
        getSessionConfig: GetSessionConfig(numRecentEvents: 7),
      );
      await expectLater(
        runner.rewindAsync(
          userId: 'u1',
          sessionId: 's_rewind',
          rewindBeforeInvocationId: 'missing',
          runConfig: runConfig,
        ),
        throwsArgumentError,
      );
      expect(
        sessionService.capturedConfigs
            .whereType<GetSessionConfig>()
            .last
            .numRecentEvents,
        7,
      );
    });

    test('runAsync fetches the session once per turn', () async {
      // Mirrors Python's test_chat_mode_fetches_session_once_per_turn
      // (commit 81306bbb): the prologue fetch is reused for the node run, so
      // there is no redundant second fetch (and no dropped session config).
      final _RecordingSessionService sessionService =
          _RecordingSessionService();
      final Runner runner = Runner(
        appName: 'app',
        agent: _RunnerTestAgent(name: 'agent'),
        sessionService: sessionService,
      );
      await sessionService.createSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's_once',
      );
      // InMemorySessionService.createSession fetches internally; only count
      // fetches made by the runner turn itself.
      sessionService.capturedConfigs.clear();

      await runner
          .runAsync(
            userId: 'u1',
            sessionId: 's_once',
            newMessage: Content.userText('hi'),
            runConfig: RunConfig(
              getSessionConfig: GetSessionConfig(numRecentEvents: 1),
            ),
          )
          .toList();

      expect(sessionService.capturedConfigs, hasLength(1));
      expect(sessionService.capturedConfigs.single?.numRecentEvents, 1);

      // Correctness: the user message is still persisted despite the single
      // fetch.
      final Session? updated = await sessionService.getSession(
        appName: 'app',
        userId: 'u1',
        sessionId: 's_once',
      );
      expect(
        updated!.events.any((Event event) => event.author == 'user'),
        isTrue,
      );
    });

    test('runDebug forwards getSessionConfig to session service', () async {
      final _RecordingSessionService sessionService =
          _RecordingSessionService();
      final Runner runner = Runner(
        appName: 'app',
        agent: _RunnerTestAgent(name: 'agent'),
        sessionService: sessionService,
      );

      final RunConfig runConfig = RunConfig(
        getSessionConfig: GetSessionConfig(numRecentEvents: 9),
      );
      final List<Event> events = await runner.runDebug(
        'hello',
        runConfig: runConfig,
        quiet: true,
      );

      expect(events, isNotEmpty);
      expect(sessionService.capturedConfigs.last?.numRecentEvents, 9);
    });
  });
}
