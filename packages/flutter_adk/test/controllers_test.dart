import 'dart:async';
import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockRunner extends adk.Runner {
  _MockRunner({this.mockStream, adk.BaseSessionService? sessionService})
      : super(
          appName: 'mock_app',
          agent: adk.LlmAgent(name: 'mock_agent', model: 'mock_model'),
          sessionService: sessionService ?? adk.InMemorySessionService(),
          autoCreateSession: true,
        );

  final Stream<adk.Event>? mockStream;

  @override
  Stream<adk.Event> runAsync({
    required String userId,
    required String sessionId,
    String? invocationId,
    adk.Content? newMessage,
    Map<String, Object?>? stateDelta,
    adk.RunConfig? runConfig,
    adk.AdkAbortSignal? abortSignal,
  }) {
    if (mockStream != null) {
      return mockStream!;
    }
    return Stream<adk.Event>.fromIterable(<adk.Event>[
      adk.Event(
        invocationId: 'inv_default',
        author: 'mock_agent',
        content: adk.Content.modelText('Hello from mock!'),
      ),
    ]);
  }
}

void main() {
  group('AdkChatController Deep Unit Tests', () {
    test('initializes with default values', () {
      final controller = AdkChatController();
      expect(controller.userId, equals('default_user'));
      expect(controller.appName, equals('default_app'));
      expect(controller.sessionId, equals('default_session'));
      expect(controller.messages, isEmpty);
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      expect(controller.currentError, isNull);
    });

    test('ignores empty or whitespace sendMessage', () async {
      final controller = AdkChatController();
      await controller.sendMessage('   ');
      expect(controller.messages, isEmpty);
    });

    test('handles missing runner gracefully by adding error message', () async {
      final controller = AdkChatController();
      await controller.sendMessage('Hello');
      expect(controller.messages.length, equals(2)); // User + Error system
      expect(controller.messages.first.isUser, isTrue);
      expect(controller.messages.last.isSystem, isTrue);
      expect(controller.currentError, isNotNull);
    });

    test('streams model response and completes turn', () async {
      final streamController = StreamController<adk.Event>();
      final mockRunner = _MockRunner(mockStream: streamController.stream);
      final controller = AdkChatController(runner: mockRunner);

      final sendFuture = controller.sendMessage('Tell me a story');

      // 1. Emit function call event
      streamController.add(
        adk.Event(
          invocationId: 'inv_1',
          author: 'mock_agent',
          content: adk.Content(
            role: 'model',
            parts: <adk.Part>[
              adk.Part(
                functionCall: adk.FunctionCall(
                  name: 'fetch_weather',
                  args: {'city': 'Seoul'},
                ),
              ),
            ],
          ),
        ),
      );

      // 2. Emit function response event
      streamController.add(
        adk.Event(
          invocationId: 'inv_2',
          author: 'Tool Result',
          content: adk.Content(
            role: 'tool',
            parts: <adk.Part>[
              adk.Part(
                functionResponse: adk.FunctionResponse(
                  name: 'fetch_weather',
                  response: {'temp': 22},
                ),
              ),
            ],
          ),
        ),
      );

      // 3. Emit first text chunk
      streamController.add(
        adk.Event(
          invocationId: 'inv_3',
          author: 'mock_agent',
          content: adk.Content.modelText('The weather in Seoul '),
        ),
      );

      // 4. Emit second text chunk
      streamController.add(
        adk.Event(
          invocationId: 'inv_4',
          author: 'mock_agent',
          content: adk.Content.modelText('is sunny today.'),
        ),
      );

      // 5. Emit event with state action and null content
      streamController.add(
        adk.Event(
          invocationId: 'inv_5',
          author: 'mock_agent',
          actions: adk.EventActions(agentState: {'step': 2}),
        ),
      );

      await streamController.close();
      await sendFuture;

      expect(controller.messages.length, greaterThanOrEqualTo(4));
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      expect(controller.currentError, isNull);

      final modelMsgs = controller.messages.where((m) => m.isModel).toList();
      expect(modelMsgs, isNotEmpty);
      expect(modelMsgs.last.text, equals('The weather in Seoul is sunny today.'));
      expect(modelMsgs.last.isStreaming, isFalse);

      final jsonTranscript = controller.exportTranscriptJson();
      expect(jsonTranscript, contains('Seoul'));
    });

    test('handles stream error gracefully', () async {
      final streamController = StreamController<adk.Event>();
      final mockRunner = _MockRunner(mockStream: streamController.stream);
      final controller = AdkChatController(runner: mockRunner);

      final sendFuture = controller.sendMessage('Trigger error');
      streamController.addError(Exception('Network timeout'));
      await streamController.close();
      await sendFuture;

      expect(controller.currentError, contains('Network timeout'));
      expect(controller.messages.any((m) => m.isSystem), isTrue);
    });

    test('clearMessages resets list and errors', () async {
      final controller = AdkChatController();
      await controller.sendMessage('Test');
      expect(controller.messages, isNotEmpty);

      controller.clearMessages();
      expect(controller.messages, isEmpty);
      expect(controller.currentError, isNull);
    });

    test('stopGeneration cancels subscription', () async {
      final streamController = StreamController<adk.Event>();
      final mockRunner = _MockRunner(mockStream: streamController.stream);
      final controller = AdkChatController(runner: mockRunner);

      // Start sending
      unawaited(controller.sendMessage('Long task'));
      expect(controller.isLoading, isTrue);

      controller.stopGeneration();
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);

      await streamController.close();
      controller.dispose();
    });
  });

  group('AdkStorageSessionService Tests', () {
    test('in-memory storage operations and session roundtrip', () async {
      final storage = AdkMemoryStorage();
      final sessionService = AdkStorageSessionService(storage: storage);

      final session = await sessionService.createSession(
        appName: 'test_app',
        userId: 'test_user',
        sessionId: 'sess_123',
        state: {'theme': 'dark'},
      );

      expect(session.id, equals('sess_123'));
      expect(session.state['theme'], equals('dark'));

      final event = adk.Event(
        invocationId: 'inv_1',
        author: 'agent',
        content: adk.Content.modelText('Hello from saved session'),
      );
      await sessionService.appendEvent(session: session, event: event);

      final retrieved = await sessionService.getSession(
        appName: 'test_app',
        userId: 'test_user',
        sessionId: 'sess_123',
      );
      expect(retrieved, isNotNull);
      expect(retrieved!.events.length, equals(1));

      final list = await sessionService.listSessions(
        appName: 'test_app',
        userId: 'test_user',
      );
      expect(list.sessions.length, equals(1));

      await sessionService.deleteSession(
        appName: 'test_app',
        userId: 'test_user',
        sessionId: 'sess_123',
      );
      final afterDelete = await sessionService.getSession(
        appName: 'test_app',
        userId: 'test_user',
        sessionId: 'sess_123',
      );
      expect(afterDelete, isNull);
    });

    test('custom storage delegate adapter', () async {
      final map = <String, String>{};
      final customService = AdkStorageSessionService.custom(
        read: (k) => map[k],
        write: (k, v) => map[k] = v,
        delete: (k) => map.remove(k),
        getKeys: ({prefix = ''}) => map.keys.where((k) => k.startsWith(prefix)).toList(),
      );

      final session = await customService.createSession(
        appName: 'app_custom',
        userId: 'u1',
        sessionId: 's1',
      );
      expect(session.id, equals('s1'));
      expect(map.keys, isNotEmpty);
    });

    test('AdkChatController.fromStorage loads previous messages', () async {
      final storage = AdkMemoryStorage();
      final agent = adk.LlmAgent(name: 'assistant', model: 'gemini');
      final sessionService = AdkStorageSessionService(storage: storage);

      final session = await sessionService.createSession(
        appName: 'app1',
        userId: 'u1',
        sessionId: 's1',
      );
      await sessionService.appendEvent(
        session: session,
        event: adk.Event(
          invocationId: 'inv_1',
          author: 'user',
          content: adk.Content.userText('Initial stored prompt'),
        ),
      );

      final controller = AdkChatController.fromStorage(
        agent: agent,
        storage: storage,
        appName: 'app1',
        userId: 'u1',
        sessionId: 's1',
      );

      await controller.loadSession();
      expect(controller.messages.length, equals(1));
      expect(controller.messages.first.text, equals('Initial stored prompt'));
    });
  });
}
