import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdkReasoningExpander Widget Tests', () {
    testWidgets('renders collapsed by default and expands on tap', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkReasoningExpander(
              thought: 'Step 1: Analyzed user intent\nStep 2: Queried database',
              durationMs: 1800,
            ),
          ),
        ),
      );

      expect(find.text('Thinking Process'), findsOneWidget);
      expect(find.text('1.8s'), findsOneWidget);
      expect(find.textContaining('Step 1: Analyzed user intent'), findsNothing);

      // Tap header to expand
      await tester.tap(find.text('Thinking Process'));
      await tester.pump();

      expect(find.textContaining('Step 1: Analyzed user intent'), findsOneWidget);
    });
  });

  group('AdkAgentPersonaSelector Widget Tests', () {
    testWidgets('renders grid personas and triggers selection', (WidgetTester tester) async {
      AdkPersona? selected;
      final agent1 = LlmAgent(name: 'coder', instruction: 'writes code');
      final agent2 = LlmAgent(name: 'writer', instruction: 'writes essays');

      final personas = [
        AdkPersona(
          id: 'p1',
          name: 'Code Expert',
          description: 'Writes clean Dart code',
          agent: agent1,
          icon: Icons.code,
        ),
        AdkPersona(
          id: 'p2',
          name: 'Writer',
          description: 'Generates creative copy',
          agent: agent2,
          icon: Icons.edit,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentPersonaSelector(
              personas: personas,
              onPersonaSelected: (p) => selected = p,
            ),
          ),
        ),
      );

      expect(find.text('Code Expert'), findsOneWidget);
      expect(find.text('Writer'), findsOneWidget);

      await tester.tap(find.text('Code Expert'));
      await tester.pump();

      expect(selected?.id, equals('p1'));
    });
  });

  group('AdkInlineAssistantBar Widget Tests', () {
    testWidgets('renders actions and triggers inline execution', (WidgetTester tester) async {
      final agent = LlmAgent(name: 'helper', instruction: 'helpful');
      final textController = TextEditingController(text: 'i is go to store');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(controller: textController),
                AdkInlineAssistantBar(
                  agent: agent,
                  targetController: textController,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Fix Grammar'), findsOneWidget);
      expect(find.text('Make Formal'), findsOneWidget);
      expect(find.text('Summarize'), findsOneWidget);
    });
  });

  group('AdkSmartFormView Widget Tests', () {
    testWidgets('renders smart form summary card and fields', (WidgetTester tester) async {
      final agent = LlmAgent(name: 'form_assistant', instruction: 'collects user info');
      Map<String, String>? submittedData;

      final fields = [
        const AdkFormField(key: 'name', label: 'Full Name', value: 'Alice'),
        const AdkFormField(key: 'email', label: 'Email', value: 'alice@example.com'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkSmartFormView(
              agent: agent,
              fields: fields,
              onSubmit: (data) => submittedData = data,
            ),
          ),
        ),
      );

      expect(find.text('Application Form'), findsOneWidget);
      expect(find.text('2 / 2 completed'), findsOneWidget);
      expect(find.text('Submit Form'), findsOneWidget);

      await tester.tap(find.text('Submit Form'));
      await tester.pump();

      expect(submittedData?['name'], equals('Alice'));
      expect(submittedData?['email'], equals('alice@example.com'));
    });
  });

  group('AdkBottomSheetChat Widget Tests', () {
    testWidgets('renders bottom sheet chat modal', (WidgetTester tester) async {
      final agent = LlmAgent(name: 'modal_agent', instruction: 'support');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showAdkChatBottomSheet(
                      context: context,
                      agent: agent,
                      title: 'Support Modal',
                    );
                  },
                  child: const Text('Open Sheet'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Support Modal'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('AdkSplitPaneView Widget Tests', () {
    testWidgets('renders adaptive split pane on wide screen', (WidgetTester tester) async {
      final agent = LlmAgent(name: 'split_agent', instruction: 'split');

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkSplitPaneView(
              agent: agent,
              breakpoint: 600.0,
            ),
          ),
        ),
      );

      expect(find.byType(AdkChatView), findsOneWidget);
      expect(find.text('Logger'), findsOneWidget);
      expect(find.text('Tools'), findsOneWidget);
    });
  });
}
