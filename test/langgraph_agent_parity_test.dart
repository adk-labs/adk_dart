import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('LangGraphAgent parity', () {
    test(
      'builds conversation messages and returns graph response event',
      () async {
        final List<LangGraphMessage> captured = <LangGraphMessage>[];
        final LangGraphAgent agent = LangGraphAgent(
          name: 'langgraph_agent',
          instruction: 'system instruction',
          hasCheckpointer: false,
          hasExistingGraphState: (_) => false,
          invokeGraph:
              ({
                required List<LangGraphMessage> messages,
                required String threadId,
              }) {
                captured
                  ..clear()
                  ..addAll(messages);
                expect(threadId, 'session-1');
                return 'graph answer';
              },
        );

        final Session session = Session(
          id: 'session-1',
          appName: 'app',
          userId: 'user',
          events: <Event>[
            Event(
              invocationId: 'inv-0',
              author: 'user',
              content: Content.userText('hello').copyWith(role: 'user'),
            ),
            Event(
              invocationId: 'inv-0',
              author: 'langgraph_agent',
              content: Content.modelText('hi there'),
            ),
            Event(
              invocationId: 'inv-0',
              author: 'other_agent',
              content: Content.modelText('ignored'),
            ),
          ],
        );

        final InvocationContext context = InvocationContext(
          sessionService: _FakeSessionService(),
          invocationId: 'inv-1',
          agent: agent,
          session: session,
        );

        final List<Event> events = await agent.runAsync(context).toList();

        expect(events, hasLength(1));
        expect(events.first.author, 'langgraph_agent');
        expect(events.first.content!.parts.first.text, 'graph answer');

        expect(
          captured.map((LangGraphMessage message) => message.role).toList(),
          <LangGraphMessageRole>[
            LangGraphMessageRole.system,
            LangGraphMessageRole.user,
            LangGraphMessageRole.assistant,
          ],
        );
        expect(captured[0].content, 'system instruction');
        expect(captured[1].content, 'hello');
        expect(captured[2].content, 'hi there');
      },
    );

    test('checkpointer mode sends only trailing user messages', () async {
      final List<LangGraphMessage> captured = <LangGraphMessage>[];
      final LangGraphAgent agent = LangGraphAgent(
        name: 'langgraph_agent',
        hasCheckpointer: true,
        invokeGraph:
            ({
              required List<LangGraphMessage> messages,
              required String threadId,
            }) {
              captured
                ..clear()
                ..addAll(messages);
              return 'ok';
            },
      );

      final Session session = Session(
        id: 'session-2',
        appName: 'app',
        userId: 'user',
        events: <Event>[
          Event(
            invocationId: 'inv-0',
            author: 'user',
            content: Content.userText('old user'),
          ),
          Event(
            invocationId: 'inv-0',
            author: 'langgraph_agent',
            content: Content.modelText('old assistant'),
          ),
          Event(
            invocationId: 'inv-0',
            author: 'user',
            content: Content.userText('latest one'),
          ),
          Event(
            invocationId: 'inv-0',
            author: 'user',
            content: Content.userText('latest two'),
          ),
        ],
      );

      final InvocationContext context = InvocationContext(
        sessionService: _FakeSessionService(),
        invocationId: 'inv-2',
        agent: agent,
        session: session,
      );

      await agent.runAsync(context).toList();

      expect(
        captured.map((LangGraphMessage message) => message.role).toList(),
        <LangGraphMessageRole>[
          LangGraphMessageRole.user,
          LangGraphMessageRole.user,
        ],
      );
      expect(
        captured.map((LangGraphMessage message) => message.content).toList(),
        <String>['latest one', 'latest two'],
      );
    });

    test(
      'suppresses system instruction when graph state already exists',
      () async {
        final List<LangGraphMessage> captured = <LangGraphMessage>[];
        final LangGraphAgent agent = LangGraphAgent(
          name: 'langgraph_agent',
          instruction: 'do not repeat',
          hasExistingGraphState: (_) => true,
          invokeGraph:
              ({
                required List<LangGraphMessage> messages,
                required String threadId,
              }) {
                captured
                  ..clear()
                  ..addAll(messages);
                return 'done';
              },
        );

        final Session session = Session(
          id: 'session-3',
          appName: 'app',
          userId: 'user',
          events: <Event>[
            Event(
              invocationId: 'inv-0',
              author: 'user',
              content: Content.userText('hello'),
            ),
          ],
        );

        final InvocationContext context = InvocationContext(
          sessionService: _FakeSessionService(),
          invocationId: 'inv-3',
          agent: agent,
          session: session,
        );

        await agent.runAsync(context).toList();

        expect(
          captured.any(
            (LangGraphMessage message) =>
                message.role == LangGraphMessageRole.system,
          ),
          isFalse,
        );
      },
    );
  });
}

class _FakeSessionService extends BaseSessionService {
  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) async {
    return Session(
      id: sessionId ?? 'session',
      appName: appName,
      userId: userId,
      state: state,
    );
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {}

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) async {
    return null;
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) async {
    return ListSessionsResponse();
  }
}
