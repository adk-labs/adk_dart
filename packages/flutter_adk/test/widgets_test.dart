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
        toolArgs: <String, dynamic>{'a': 1, 'b': 2},
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

  group('Adk UI Kit Widget tests', () {
    testWidgets('renders AdkMessageBubble for user and model', (WidgetTester tester) async {
      final userMsg = AdkChatMessage.user(id: 'u1', text: 'User question');
      final modelMsg = AdkChatMessage.model(id: 'm1', text: 'Agent answer');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
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

    testWidgets('renders AdkPromptSuggestionsBar and triggers selection', (WidgetTester tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkPromptSuggestionsBar(
              suggestions: const <String>['Summarize', 'Help code', 'Draft email'],
              onSelected: (String val) => selected = val,
            ),
          ),
        ),
      );

      expect(find.text('Summarize'), findsOneWidget);
      expect(find.text('Help code'), findsOneWidget);

      await tester.tap(find.text('Summarize'));
      expect(selected, 'Summarize');
    });

    testWidgets('renders AdkToolCallCard and expands details', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkToolCallCard(
              toolName: 'web_search',
              toolArgs: <String, dynamic>{'query': 'Flutter ADK'},
              toolResult: 'Found results',
              initiallyExpanded: true,
            ),
          ),
        ),
      );

      expect(find.text('Tool: web_search'), findsOneWidget);
      expect(find.text('Success'), findsOneWidget);
      expect(find.text('Arguments:'), findsOneWidget);
      expect(find.text('Result:'), findsOneWidget);
    });

    testWidgets('renders AdkConfirmationBanner and handles actions', (WidgetTester tester) async {
      bool confirmed = false;
      bool denied = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkConfirmationBanner(
              title: 'Confirm Transaction',
              description: 'Transfer 10 USD to Alice?',
              toolName: 'transfer_money',
              onConfirm: () => confirmed = true,
              onDeny: () => denied = true,
            ),
          ),
        ),
      );

      expect(find.text('Confirm Transaction'), findsOneWidget);
      expect(find.text('Transfer 10 USD to Alice?'), findsOneWidget);

      await tester.tap(find.text('Allow'));
      expect(confirmed, isTrue);

      await tester.tap(find.text('Deny'));
      expect(denied, isTrue);
    });

    testWidgets('renders AdkFloatingChatButton', (WidgetTester tester) async {
      final agent = LlmAgent(name: 'fab_agent', model: 'gemini-2.5-flash');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: AdkFloatingChatButton(
              agent: agent,
              title: 'Floating AI',
            ),
          ),
        ),
      );

      expect(find.byType(AdkFloatingChatButton), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    });

    testWidgets('renders AdkSessionDrawer', (WidgetTester tester) async {
      String? selectedSession;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            drawer: AdkSessionDrawer(
              sessions: const <AdkSessionItem>[
                AdkSessionItem(id: 's1', title: 'First Chat'),
                AdkSessionItem(id: 's2', title: 'Second Chat'),
              ],
              activeSessionId: 's1',
              onSessionSelected: (String id) => selectedSession = id,
              onNewSession: () {},
            ),
          ),
        ),
      );

      // Open drawer
      final ScaffoldState state = tester.firstState(find.byType(Scaffold));
      state.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Conversations'), findsOneWidget);
      expect(find.text('First Chat'), findsOneWidget);
      expect(find.text('Second Chat'), findsOneWidget);

      await tester.tap(find.text('Second Chat'));
      expect(selectedSession, 's2');
    });

    testWidgets('renders AdkAgentHierarchyBadge', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkAgentHierarchyBadge(
              agentPath: <String>['Orchestrator', 'Researcher', 'PythonCoder'],
            ),
          ),
        ),
      );

      expect(find.text('Orchestrator'), findsOneWidget);
      expect(find.text('Researcher'), findsOneWidget);
      expect(find.text('PythonCoder'), findsOneWidget);
    });

    testWidgets('renders AdkWorkflowProgressIndicator', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkWorkflowProgressIndicator(
              steps: <AdkWorkflowStep>[
                AdkWorkflowStep(
                  name: 'Fetch Data',
                  status: AdkWorkflowNodeStatus.completed,
                ),
                AdkWorkflowStep(
                  name: 'Analyze Data',
                  status: AdkWorkflowNodeStatus.running,
                ),
                AdkWorkflowStep(
                  name: 'Generate Report',
                  status: AdkWorkflowNodeStatus.pending,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Fetch Data'), findsOneWidget);
      expect(find.text('Analyze Data'), findsOneWidget);
      expect(find.text('Generate Report'), findsOneWidget);
    });

    testWidgets('renders AdkVoiceMicButton and AdkAudioWaveVisualizer', (WidgetTester tester) async {
      bool micTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: <Widget>[
                AdkVoiceMicButton(
                  isListening: true,
                  onPressed: () => micTapped = true,
                ),
                const AdkAudioWaveVisualizer(isActive: true),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(AdkVoiceMicButton), findsOneWidget);
      expect(find.byType(AdkAudioWaveVisualizer), findsOneWidget);

      await tester.tap(find.byType(AdkVoiceMicButton));
      expect(micTapped, isTrue);
    });

    testWidgets('renders AdkTokenUsageBadge', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkTokenUsageBadge(
              promptTokens: 120,
              candidatesTokens: 350,
              estimatedCost: '\$0.001',
            ),
          ),
        ),
      );

      expect(find.text('470 tokens'), findsOneWidget);
    });

    testWidgets('renders AdkChatView with suggestions and input', (WidgetTester tester) async {
      final agent = LlmAgent(
        name: 'simple_agent',
        model: 'gemini-3.7-flash',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkChatView(
              agent: agent,
              title: 'Test Assistant',
              suggestions: const <String>['Quick prompt'],
              showAppBar: true,
            ),
          ),
        ),
      );

      expect(find.text('Test Assistant'), findsOneWidget);
      expect(find.text('Quick prompt'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Hello AI');
      expect(find.text('Hello AI'), findsOneWidget);
    });

    testWidgets('renders AdkAgentLoggerView and displays logs', (WidgetTester tester) async {
      final logs = <AdkAgentLogEntry>[
        AdkAgentLogEntry(
          id: 'log1',
          timestamp: DateTime.now(),
          agentName: 'researcher',
          category: AdkLogCategory.modelResponse,
          title: 'Generated analysis',
          payload: <String, dynamic>{'status': 'ok'},
          durationMs: 145,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentLoggerView(logs: logs),
          ),
        ),
      );

      expect(find.text('Agent I/O Logger'), findsOneWidget);
      expect(find.text('researcher'), findsOneWidget);
      expect(find.text('Generated analysis'), findsOneWidget);
      expect(find.text('145ms'), findsOneWidget);
    });

    testWidgets('renders AdkDevStudioView with tabs and components', (WidgetTester tester) async {
      final agent = LlmAgent(
        name: 'studio_agent',
        model: 'gemini-3.7-flash',
        description: 'Test Studio Agent',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AdkDevStudioView(
            agent: agent,
            title: 'Custom Dev Studio',
          ),
        ),
      );

      expect(find.text('Custom Dev Studio'), findsOneWidget);
      expect(find.text('Playground'), findsOneWidget);
      expect(find.text('Live Logger'), findsOneWidget);
      expect(find.text('Agent Graph'), findsOneWidget);
      expect(find.text('State & Session'), findsOneWidget);

      // Switch to Agent Graph tab
      await tester.tap(find.text('Agent Graph'));
      await tester.pumpAndSettle();

      expect(find.text('studio_agent'), findsOneWidget);
      expect(find.text('Test Studio Agent'), findsOneWidget);
    });
  });
}
