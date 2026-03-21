import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

class _StubRunner extends Runner {
  _StubRunner(this._streamFactory)
    : super(
        appName: 'slack_app',
        agent: Agent(name: 'root_agent', model: _NoopModel()),
        sessionService: InMemorySessionService(),
        autoCreateSession: true,
      );

  final Stream<Event> Function({
    required String userId,
    required String sessionId,
    required Content newMessage,
  })
  _streamFactory;

  String? lastUserId;
  String? lastSessionId;
  Content? lastMessage;

  @override
  Stream<Event> runAsync({
    required String userId,
    required String sessionId,
    String? invocationId,
    Content? newMessage,
    Map<String, Object?>? stateDelta,
    RunConfig? runConfig,
  }) {
    lastUserId = userId;
    lastSessionId = sessionId;
    lastMessage = newMessage;
    return _streamFactory(
      userId: userId,
      sessionId: sessionId,
      newMessage: newMessage ?? Content(),
    );
  }
}

class _FakeSlackApiClient implements SlackApiClient {
  final List<Map<String, String>> updates = <Map<String, String>>[];
  final List<Map<String, String>> deletes = <Map<String, String>>[];

  @override
  Future<void> chatDelete({required String channel, required String ts}) async {
    deletes.add(<String, String>{'channel': channel, 'ts': ts});
  }

  @override
  Future<void> chatUpdate({
    required String channel,
    required String ts,
    required String text,
  }) async {
    updates.add(<String, String>{'channel': channel, 'ts': ts, 'text': text});
  }
}

class _FakeSlackApp implements SlackAppAdapter {
  @override
  final _FakeSlackApiClient client = _FakeSlackApiClient();

  final Map<String, SlackEventHandler> handlers = <String, SlackEventHandler>{};

  @override
  void onEvent(String eventName, SlackEventHandler handler) {
    handlers[eventName] = handler;
  }

  Future<void> emit(
    String eventName,
    Map<String, Object?> event,
    SlackSay say,
  ) async {
    final SlackEventHandler? handler = handlers[eventName];
    if (handler == null) {
      fail('Missing handler for $eventName');
    }
    await handler(event, say);
  }
}

class _FakeSocketModeHandler implements SlackSocketModeHandler {
  bool started = false;

  @override
  Future<void> start() async {
    started = true;
  }
}

void main() {
  group('SlackRunner', () {
    test('handles app mentions and updates the thinking message', () async {
      final _StubRunner runner = _StubRunner(({
        required String userId,
        required String sessionId,
        required Content newMessage,
      }) {
        return Stream<Event>.value(
          Event(
            invocationId: 'inv-1',
            author: 'root_agent',
            content: Content.modelText('Hi user!'),
          ),
        );
      });
      final _FakeSlackApp slackApp = _FakeSlackApp();
      SlackRunner(runner, slackApp);
      final List<Map<String, Object?>> sayCalls = <Map<String, Object?>>[];

      await slackApp.emit(
        'app_mention',
        <String, Object?>{
          'text': 'Hello bot',
          'user': 'U12345',
          'channel': 'C67890',
          'ts': '1234567890.123456',
        },
        ({required String text, String? threadTs}) async {
          sayCalls.add(<String, Object?>{'text': text, 'threadTs': threadTs});
          return <String, Object?>{'ts': 'thinking_ts'};
        },
      );

      expect(runner.lastUserId, 'U12345');
      expect(runner.lastSessionId, 'C67890-1234567890.123456');
      expect(runner.lastMessage?.parts.single.text, 'Hello bot');
      expect(sayCalls, <Map<String, Object?>>[
        <String, Object?>{
          'text': '_Thinking..._',
          'threadTs': '1234567890.123456',
        },
      ]);
      expect(slackApp.client.updates, <Map<String, String>>[
        <String, String>{
          'channel': 'C67890',
          'ts': 'thinking_ts',
          'text': 'Hi user!',
        },
      ]);
      expect(slackApp.client.deletes, isEmpty);
    });

    test('message handler ignores bot and non-thread channel events', () async {
      final _StubRunner runner = _StubRunner(({
        required String userId,
        required String sessionId,
        required Content newMessage,
      }) {
        fail('Runner should not be called for ignored events.');
      });
      final _FakeSlackApp slackApp = _FakeSlackApp();
      SlackRunner(runner, slackApp);

      await slackApp.emit(
        'message',
        <String, Object?>{
          'bot_id': 'B123',
          'text': 'ignore me',
          'user': 'U12345',
          'channel': 'C67890',
          'channel_type': 'im',
          'ts': '1',
        },
        ({required String text, String? threadTs}) async {
          fail('say should not be called for ignored events');
        },
      );

      await slackApp.emit(
        'message',
        <String, Object?>{
          'text': 'ignore me too',
          'user': 'U12345',
          'channel': 'C67890',
          'channel_type': 'channel',
          'ts': '2',
        },
        ({required String text, String? threadTs}) async {
          fail('say should not be called for ignored events');
        },
      );
    });

    test('handles multi-turn responses in the same thread', () async {
      final _StubRunner runner = _StubRunner(({
        required String userId,
        required String sessionId,
        required Content newMessage,
      }) {
        return Stream<Event>.fromIterable(<Event>[
          Event(
            invocationId: 'inv-1',
            author: 'root_agent',
            content: Content.modelText('First thing.'),
          ),
          Event(
            invocationId: 'inv-1',
            author: 'root_agent',
            content: Content.modelText('Second thing.'),
          ),
        ]);
      });
      final _FakeSlackApp slackApp = _FakeSlackApp();
      SlackRunner(runner, slackApp);
      final List<Map<String, Object?>> sayCalls = <Map<String, Object?>>[];

      await slackApp.emit(
        'message',
        <String, Object?>{
          'text': 'Tell me two things',
          'user': 'U12345',
          'channel': 'C67890',
          'channel_type': 'im',
          'ts': '1234567890.123456',
        },
        ({required String text, String? threadTs}) async {
          sayCalls.add(<String, Object?>{'text': text, 'threadTs': threadTs});
          return <String, Object?>{'ts': 'thinking_ts'};
        },
      );

      expect(slackApp.client.updates, <Map<String, String>>[
        <String, String>{
          'channel': 'C67890',
          'ts': 'thinking_ts',
          'text': 'First thing.',
        },
      ]);
      expect(sayCalls, <Map<String, Object?>>[
        <String, Object?>{
          'text': '_Thinking..._',
          'threadTs': '1234567890.123456',
        },
        <String, Object?>{
          'text': 'Second thing.',
          'threadTs': '1234567890.123456',
        },
      ]);
    });

    test('updates the thinking message on runner errors', () async {
      final _StubRunner runner = _StubRunner(({
        required String userId,
        required String sessionId,
        required Content newMessage,
      }) {
        return Stream<Event>.error(Exception('Something went wrong'));
      });
      final _FakeSlackApp slackApp = _FakeSlackApp();
      SlackRunner(runner, slackApp);

      await slackApp.emit(
        'message',
        <String, Object?>{
          'text': 'Trigger error',
          'user': 'U12345',
          'channel': 'C67890',
          'channel_type': 'im',
          'ts': '1234567890.123456',
        },
        ({required String text, String? threadTs}) async {
          return <String, Object?>{'ts': 'thinking_ts'};
        },
      );

      expect(slackApp.client.updates, hasLength(1));
      expect(
        slackApp.client.updates.single['text'],
        contains('Sorry, I encountered an error'),
      );
    });

    test('starts socket mode through the configured factory', () async {
      final _StubRunner runner = _StubRunner(({
        required String userId,
        required String sessionId,
        required Content newMessage,
      }) {
        return const Stream<Event>.empty();
      });
      final _FakeSlackApp slackApp = _FakeSlackApp();
      final _FakeSocketModeHandler handler = _FakeSocketModeHandler();
      final SlackRunner slackRunner = SlackRunner(
        runner,
        slackApp,
        socketModeHandlerFactory: (SlackAppAdapter app, String appToken) {
          expect(app, same(slackApp));
          expect(appToken, 'xapp-test-token');
          return handler;
        },
      );

      await slackRunner.start('xapp-test-token');

      expect(handler.started, isTrue);
    });
  });
}
