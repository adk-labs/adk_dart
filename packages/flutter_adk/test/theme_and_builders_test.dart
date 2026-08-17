import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdkTheme and AdkChatThemeData Tests', () {
    testWidgets('AdkTheme cascades theme data down the widget tree', (WidgetTester tester) async {
      const customTheme = AdkChatThemeData(
        userBubbleColor: Colors.deepPurple,
        modelBubbleColor: Colors.amber,
        userTextColor: Colors.white,
        modelTextColor: Colors.black,
        showTimestamp: true,
      );

      late AdkChatThemeData retrieved;

      await tester.pumpWidget(
        MaterialApp(
          home: AdkTheme(
            data: customTheme,
            child: Builder(
              builder: (context) {
                retrieved = AdkTheme.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(retrieved.userBubbleColor, equals(Colors.deepPurple));
      expect(retrieved.modelBubbleColor, equals(Colors.amber));
      expect(retrieved.showTimestamp, isTrue);
    });

    test('AdkChatThemeData copyWith works correctly', () {
      const theme1 = AdkChatThemeData(
        userBubbleColor: Colors.blue,
        modelBubbleColor: Colors.grey,
        showAvatars: false,
      );

      final updated = theme1.copyWith(
        userBubbleColor: Colors.red,
        showAvatars: true,
      );

      expect(updated.userBubbleColor, equals(Colors.red));
      expect(updated.modelBubbleColor, equals(Colors.grey));
      expect(updated.showAvatars, isTrue);
    });
  });

  group('Custom Builders Widget Tests in AdkChatView and AdkMessageBubble', () {
    testWidgets('renders custom avatar and timestamp in AdkMessageBubble', (WidgetTester tester) async {
      final userMsg = AdkChatMessage.user(
        id: '1',
        text: 'Hello with avatar',
        timestamp: DateTime(2026, 8, 17, 14, 30),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkMessageBubble(
              message: userMsg,
              showAvatar: true,
              avatarBuilder: (context, msg) => const KeyedSubtree(
                key: Key('custom_user_avatar'),
                child: CircleAvatar(child: Text('U')),
              ),
              showTimestamp: true,
              timestampFormatter: (t) => 'CUSTOM_TIME_14:30',
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('custom_user_avatar')), findsOneWidget);
      expect(find.text('CUSTOM_TIME_14:30'), findsOneWidget);
      expect(find.text('Hello with avatar'), findsOneWidget);
    });

    testWidgets('AdkChatView supports custom emptyStateBuilder, inputBarBuilder, and suggestionBuilder',
        (WidgetTester tester) async {
      final agent = LlmAgent(name: 'test_agent', instruction: 'test');

      bool customSendTapped = false;
      bool customSuggestionTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkChatView(
              agent: agent,
              suggestions: const ['Plan Trip', 'Write Code'],
              emptyStateBuilder: (context) => const Center(
                child: Text('CUSTOM_EMPTY_ONBOARDING'),
              ),
              suggestionBuilder: (context, suggestion, onSelect) => TextButton(
                key: Key('sug_$suggestion'),
                onPressed: () {
                  customSuggestionTapped = true;
                  onSelect();
                },
                child: Text('CHIP: $suggestion'),
              ),
              inputBarBuilder: (context, controller, onSend, isLoading) => Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('custom_input'),
                      controller: controller,
                    ),
                  ),
                  IconButton(
                    key: const Key('custom_send_btn'),
                    icon: const Icon(Icons.send),
                    onPressed: () {
                      customSendTapped = true;
                      onSend();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('CUSTOM_EMPTY_ONBOARDING'), findsOneWidget);
      expect(find.text('CHIP: Plan Trip'), findsOneWidget);
      expect(find.text('CHIP: Write Code'), findsOneWidget);
      expect(find.byKey(const Key('custom_input')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sug_Plan Trip')));
      await tester.pump();
      expect(customSuggestionTapped, isTrue);

      await tester.enterText(find.byKey(const Key('custom_input')), 'Custom message test');
      await tester.tap(find.byKey(const Key('custom_send_btn')));
      await tester.pump();
      expect(customSendTapped, isTrue);
    });

    testWidgets('AdkPromptSuggestionsBar renders custom chipBuilder', (WidgetTester tester) async {
      String? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkPromptSuggestionsBar(
              suggestions: const ['Opt1', 'Opt2'],
              onSelected: (val) => selected = val,
              chipBuilder: (context, sug, onSelect) => ElevatedButton(
                key: Key('btn_$sug'),
                onPressed: onSelect,
                child: Text('CUSTOM_$sug'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('CUSTOM_Opt1'), findsOneWidget);
      expect(find.text('CUSTOM_Opt2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_Opt1')));
      expect(selected, equals('Opt1'));
    });
  });
}
