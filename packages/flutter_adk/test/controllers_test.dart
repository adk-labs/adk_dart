import 'dart:async';
import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockRunner extends adk.Runner {
  _MockRunner({this.mockStream})
      : super(
          appName: 'mock_app',
          agent: adk.LlmAgent(name: 'mock_agent', model: 'mock_model'),
          sessionService: adk.InMemorySessionService(),
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
}
