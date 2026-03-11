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
