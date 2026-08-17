import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdkChatMessage tests', () {
    test('instantiates user, model, tool, and system messages', () {
      final userMsg = AdkChatMessage.user(id: '1', text: 'Hello');
      expect(userMsg.role, AdkMessageRole.user);
      expect(userMsg.text, 'Hello');

      final modelMsg = AdkChatMessage.model(id: '2', text: 'Hi there', isPartial: true);
      expect(modelMsg.role, AdkMessageRole.model);
      expect(modelMsg.isPartial, isTrue);

      final toolMsg = AdkChatMessage.tool(
        id: '3',
        toolName: 'calculator',
        toolArgs: {'a': 1, 'b': 2},
        toolResult: 3,
      );
      expect(toolMsg.role, AdkMessageRole.tool);
      expect(toolMsg.toolName, 'calculator');

      final sysMsg = AdkChatMessage.system(id: '4', text: 'Alert', errorMessage: 'Timeout');
      expect(sysMsg.role, AdkMessageRole.system);
      expect(sysMsg.errorMessage, 'Timeout');
    });
  });

  group('AdkChatController tests', () {
    test('sendMessage adds user message and notifies listeners', () async {
      final agent = LlmAgent(
        name: 'test_agent',
        model: 'gemini-2.5-flash',
      );

      final controller = AdkChatController(agent: agent);
      expect(controller.messages, isEmpty);
      expect(controller.isLoading, isFalse);

      final future = controller.sendMessage('Test prompt');
      expect(controller.messages.length, greaterThanOrEqualTo(1));
      expect(controller.messages.first.text, 'Test prompt');
      await future;

      controller.clearMessages();
      expect(controller.messages, isEmpty);
    });
  });

  group('AdkChatView and MessageBubble Widget tests', () {
    testWidgets('renders AdkMessageBubble for user and model', (WidgetTester tester) async {
      final userMsg = AdkChatMessage.user(id: 'u1', text: 'User question');
      final modelMsg = AdkChatMessage.model(id: 'm1', text: 'Agent answer');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AdkMessageBubble(message: userMsg),
                AdkMessageBubble(message: modelMsg),
              ],
            ),
          ),
        ),
      );

      expect(find.text('User question'), findsOneWidget);
      expect(find.text('Agent answer'), findsOneWidget);
    });

    testWidgets('renders AdkChatView and handles input', (WidgetTester tester) async {
      final agent = LlmAgent(
        name: 'simple_agent',
        model: 'gemini-2.5-flash',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkChatView(
              agent: agent,
              title: 'Test Assistant',
              showAppBar: true,
            ),
          ),
        ),
      );

      expect(find.text('Test Assistant'), findsOneWidget);
      expect(find.text('Ask something...'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Hello AI');
      expect(find.text('Hello AI'), findsOneWidget);
    });

    testWidgets('renders AdkTypingIndicator', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkTypingIndicator(),
          ),
        ),
      );

      expect(find.byType(AdkTypingIndicator), findsOneWidget);
    });
  });
}
