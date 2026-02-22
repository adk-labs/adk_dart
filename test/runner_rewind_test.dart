import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopAgent extends BaseAgent {
  _NoopAgent({required super.name});

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {}
}

void main() {
  test('rewindAsync rewinds state and artifacts', () async {
    final _NoopAgent root = _NoopAgent(name: 'root');
    final InMemorySessionService sessionService = InMemorySessionService();
    final InMemoryArtifactService artifactService = InMemoryArtifactService();
    final Runner runner = Runner(
      appName: 'test_app',
      agent: root,
      sessionService: sessionService,
      artifactService: artifactService,
    );

    const String userId = 'test_user';
    const String sessionId = 'test_session';
    final Session session = await runner.sessionService.createSession(
      appName: runner.appName,
      userId: userId,
      sessionId: sessionId,
    );

    await artifactService.saveArtifact(
      appName: runner.appName,
      userId: userId,
      sessionId: sessionId,
      filename: 'f1',
      artifact: Part.text('f1v0'),
    );
    await runner.sessionService.appendEvent(
      session: session,
      event: Event(
        invocationId: 'invocation1',
        author: 'agent',
        content: Content.modelText('event1'),
        actions: EventActions(
          stateDelta: <String, Object?>{'k1': 'v1'},
          artifactDelta: <String, int>{'f1': 0},
        ),
      ),
    );

    await artifactService.saveArtifact(
      appName: runner.appName,
      userId: userId,
      sessionId: sessionId,
      filename: 'f1',
      artifact: Part.text('f1v1'),
    );
    await artifactService.saveArtifact(
      appName: runner.appName,
      userId: userId,
      sessionId: sessionId,
      filename: 'f2',
      artifact: Part.text('f2v0'),
    );
    await runner.sessionService.appendEvent(
      session: session,
      event: Event(
        invocationId: 'invocation2',
        author: 'agent',
        content: Content.modelText('event2'),
        actions: EventActions(
          stateDelta: <String, Object?>{'k1': 'v2', 'k2': 'v2'},
          artifactDelta: <String, int>{'f1': 1, 'f2': 0},
        ),
      ),
    );

    await runner.sessionService.appendEvent(
      session: session,
      event: Event(
        invocationId: 'invocation3',
        author: 'agent',
        content: Content.modelText('event3'),
        actions: EventActions(stateDelta: <String, Object?>{'k2': 'v3'}),
      ),
    );

    await runner.rewindAsync(
      userId: userId,
      sessionId: sessionId,
      rewindBeforeInvocationId: 'invocation2',
    );

    final Session? rewound = await runner.sessionService.getSession(
      appName: runner.appName,
      userId: userId,
      sessionId: sessionId,
    );
    expect(rewound, isNotNull);
    expect(rewound!.state['k1'], 'v1');
    expect(rewound.state['k2'], isNull);

    final Part? f1 = await artifactService.loadArtifact(
      appName: runner.appName,
      userId: userId,
      sessionId: sessionId,
      filename: 'f1',
    );
    final Part? f2 = await artifactService.loadArtifact(
      appName: runner.appName,
      userId: userId,
      sessionId: sessionId,
      filename: 'f2',
    );
    expect(f1?.text, 'f1v0');
    expect(f2, isNull);
  });
}
