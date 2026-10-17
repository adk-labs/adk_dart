import 'dart:async';
import 'dart:convert';
import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_adk/flutter_adk.dart';

class _CoverageMockAgent extends adk.BaseAgent {
  _CoverageMockAgent({
    super.name = 'mock_agent',
    super.description = 'Mock agent for testing',
    super.subAgents = const <adk.BaseAgent>[],
  });

  Stream<adk.Event> Function(adk.InvocationContext context)? onRun;

  @override
  Stream<adk.Event> runAsyncImpl(adk.InvocationContext context) async* {
    if (onRun != null) {
      yield* onRun!(context);
    } else {
      yield adk.Event(
        id: 'evt_1',
        invocationId: 'inv_1',
        author: name,
        content: adk.Content.modelText('Response'),
      );
    }
  }
}

class _CoverageMockRunner extends adk.Runner {
  _CoverageMockRunner({
    required super.agent,
    this.streamFactory,
  }) : super(
         appName: 'CoverageMockRunner',
         artifactService: adk.InMemoryArtifactService(),
         sessionService: adk.InMemorySessionService(),
         autoCreateSession: true,
       );

  final Stream<adk.Event> Function()? streamFactory;

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
    if (streamFactory != null) {
      return streamFactory!();
    }
    return super.runAsync(
      userId: userId,
      sessionId: sessionId,
      invocationId: invocationId,
      newMessage: newMessage,
      stateDelta: stateDelta,
      runConfig: runConfig,
      abortSignal: abortSignal,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdkAgentLoggerView and Controller 100% tests', () {
    testWidgets('didUpdateWidget autoScroll, toggle autoScroll, clear, formatPayload, expand & copy', (WidgetTester tester) async {
      bool cleared = false;
      final logs = <AdkAgentLogEntry>[
        AdkAgentLogEntry(
          id: 'log_1',
          timestamp: DateTime.now(),
          agentName: 'AgentA',
          category: AdkLogCategory.toolCall,
          title: 'Tool Call',
          subtitle: 'Executing tool',
          payload: {'status': 'ok'},
          isError: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentLoggerView(
              logs: logs,
              onClearLogs: () => cleared = true,
            ),
          ),
        ),
      );

      expect(find.text('Tool Call'), findsOneWidget);

      // Toggle auto-scroll button
      await tester.tap(find.byIcon(Icons.vertical_align_bottom));
      await tester.pump();

      // Clear button
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      expect(cleared, true);

      // Expand tile to show subtitle, copy button, and payload
      await tester.tap(find.text('Tool Call'));
      await tester.pumpAndSettle();

      expect(find.text('Executing tool'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);

      // Tap copy payload
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();

      // Trigger didUpdateWidget with new log
      final updatedLogs = List<AdkAgentLogEntry>.from(logs)
        ..add(
          AdkAgentLogEntry(
            id: 'log_2',
            timestamp: DateTime.now(),
            agentName: 'AgentB',
            category: AdkLogCategory.error,
            title: 'Error Log',
            payload: 'raw_string_payload',
            isError: true,
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentLoggerView(
              logs: updatedLogs,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Error Log'), findsOneWidget);

      // Expand error log with string payload
      await tester.tap(find.text('Error Log'));
      await tester.pumpAndSettle();
      expect(find.text('"raw_string_payload"'), findsOneWidget);

      // Test all categories in view
      final categoryLogs = <AdkAgentLogEntry>[
        AdkAgentLogEntry(id: 'c1', timestamp: DateTime.now(), agentName: 'A', category: AdkLogCategory.stateUpdate, title: 'State'),
        AdkAgentLogEntry(id: 'c2', timestamp: DateTime.now(), agentName: 'A', category: AdkLogCategory.error, title: 'Err', isError: true),
        AdkAgentLogEntry(id: 'c3', timestamp: DateTime.now(), agentName: 'A', category: AdkLogCategory.all, title: 'All'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentLoggerView(logs: categoryLogs),
          ),
        ),
      );
      expect(find.text('State'), findsOneWidget);
      expect(find.text('Err'), findsOneWidget);
    });

    test('AdkAgentLoggerController searchQuery getter', () {
      final controller = AdkAgentLoggerController();
      expect(controller.searchQuery, '');
      controller.setSearchQuery('test');
      expect(controller.searchQuery, 'test');
    });
  });

  group('AdkDevStudioView 100% tests', () {
    testWidgets('processes chat updates for logs, tools tab, sub-agents without instruction, and clear', (WidgetTester tester) async {
      final subAgent = _CoverageMockAgent(name: 'sub_worker', description: '');
      final mainAgent = _CoverageMockAgent(
        name: 'studio_agent',
        subAgents: [subAgent],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkDevStudioView(
              agent: mainAgent,
              initialTabIndex: 2,
            ),
          ),
        ),
      );

      expect(find.byType(AdkDevStudioView), findsOneWidget);
      expect(find.text('sub_worker'), findsOneWidget);
      expect(find.text('Type: _CoverageMockAgent'), findsOneWidget);

      // Agent graph fallback when agent is null
      final chatCtrl = AdkChatController(agent: mainAgent);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkDevStudioView(
              controller: chatCtrl,
              initialTabIndex: 2,
            ),
          ),
        ),
      );
      expect(find.text('Agent metadata not available.'), findsOneWidget);
    });

    testWidgets('simulates message updates across all roles and tool payload paths in AdkDevStudioView', (WidgetTester tester) async {
      final agent = _CoverageMockAgent(name: 'chat_dev_agent');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkDevStudioView(agent: agent),
          ),
        ),
      );

      // In chat view, send messages
      await tester.enterText(find.byType(TextField), 'Hello studio');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      // Switch to Live Logger tab to verify log entry
      await tester.tap(find.text('Live Logger'));
      await tester.pumpAndSettle();
      expect(find.text('Hello studio'), findsWidgets);
    });
  });

  group('AdkAgentManagementView 100% tests', () {
    testWidgets('headerBuilder, search clear, tag selection, empty state, cardBuilder, and status colors', (WidgetTester tester) async {
      final a1 = _CoverageMockAgent(name: 'agent_alpha');
      final a2 = _CoverageMockAgent(name: 'agent_beta');
      final controller = AdkAgentManagerController(initialAgents: [a1, a2]);

      controller.setAgentStatus('agent_alpha', AdkAgentStatus.busy);
      controller.setAgentStatus('agent_beta', AdkAgentStatus.disabled);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentManagementView(
              controller: controller,
              headerBuilder: (ctx) => const Text('Custom Header Agents'),
            ),
          ),
        ),
      );

      expect(find.text('Custom Header Agents'), findsOneWidget);

      // Search input and clear button
      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pump();
      expect(controller.searchQuery, 'alpha');
      expect(find.byIcon(Icons.clear), findsOneWidget);

      // Clear search button
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(controller.searchQuery, '');

      // Toggle switch
      await tester.tap(find.byType(Switch).first);
      await tester.pump();

      // Test empty state
      controller.setSearchQuery('non_existent');
      await tester.pump();
      expect(find.text('No agents found'), findsOneWidget);

      // Test custom emptyStateBuilder
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentManagementView(
              controller: controller,
              emptyStateBuilder: (ctx) => const Text('Empty Custom Builder'),
            ),
          ),
        ),
      );
      expect(find.text('Empty Custom Builder'), findsOneWidget);

      // Test agentCardBuilder
      controller.setSearchQuery('');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentManagementView(
              controller: controller,
              agentCardBuilder: (ctx, meta, toggle, inspect) => ListTile(
                title: Text('CustomCard: ${meta.name}'),
                onTap: inspect,
              ),
            ),
          ),
        ),
      );
      expect(find.text('CustomCard: agent_alpha'), findsOneWidget);
    });
  });

  group('AdkUIUtils 100% tests', () {
    test('formatJson, extractOpenInterrupts, token extraction, and model consult', () {
      // Formatters
      expect(AdkFormatters.formatJson('non_json_string'), '"non_json_string"');

      // Interrupt utils
      final events = <adk.Event>[
        adk.Event(
          id: 'int_1',
          invocationId: 'inv_1',
          author: 'system',
          longRunningToolIds: const {'call_1'},
          actions: adk.EventActions(
            requestedToolConfirmations: {
              'call_1': {'hint': 'Confirm execute'},
            },
          ),
        ),
      ];
      expect(AdkEventStreamUtils.hasOpenInterrupts(events), true);
      expect(AdkEventStreamUtils.extractOpenInterrupts(events).isNotEmpty, true);
      expect(AdkEventStreamUtils.hasOpenInterrupts([]), false);

      // Token utils with completion_tokens, totalTokenCount, thoughtTokens
      final tokenMap = {
        'promptTokenCount': 10,
        'completion_tokens': 20,
        'totalTokenCount': 30,
        'thoughtTokens': 5,
      };
      final parsedTokens = AdkEventStreamUtils.extractTokenUsage(
        adk.Event(
          id: 'e',
          invocationId: 'i',
          author: 'a',
          usageMetadata: tokenMap,
        ),
      );
      expect(parsedTokens?.totalTokens, 30);
      expect(parsedTokens?.thoughtTokens, 5);

      // Dynamic object with snake_case tokens
      final dynObj = _FakeUsageObj(prompt: 15, candidates: 25, total: 40);
      final parsedObjTokens = AdkEventStreamUtils.extractTokenUsage(
        adk.Event(
          id: 'e2',
          invocationId: 'i',
          author: 'a',
          usageMetadata: dynObj,
        ),
      );
      expect(parsedObjTokens?.totalTokens, 40);

      // Model consult escalation and function call extraction
      final consultEvent = adk.Event(
        id: 'e3',
        invocationId: 'i',
        author: 'a',
        content: adk.Content(
          role: 'model',
          parts: [
            adk.Part(
              functionCall: adk.FunctionCall(
                id: 'fc1',
                name: 'consult_model',
                args: {'advisor_model': 'gemini-1.5-pro', 'reason': 'complex task'},
              ),
            ),
          ],
        ),
        customMetadata: {'escalated': true},
      );
      expect(AdkEventStreamUtils.isModelConsultEvent(consultEvent), true);
      final advisorInfo = AdkEventStreamUtils.extractModelConsultInfo(consultEvent);
      expect(advisorInfo.advisorModel, 'gemini-1.5-pro');
      expect(advisorInfo.escalationReason, 'complex task');
    });
  });

  group('AdkSplitPaneView 100% tests', () {
    testWidgets('onChatUpdate, mapRoleToCategory, leftPaneBuilder, rightPaneBuilder, and clear logs', (WidgetTester tester) async {
      final agent = _CoverageMockAgent();
      final controller = AdkChatController(agent: agent);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkSplitPaneView(
              agent: agent,
              controller: controller,
              breakpoint: 200,
              showLogger: true,
              leftPaneBuilder: (ctx, ctrl) => const Text('Custom Left Pane'),
              rightPaneBuilder: (ctx, ctrl) => const Text('Custom Right Pane'),
            ),
          ),
        ),
      );

      expect(find.text('Custom Left Pane'), findsOneWidget);
      expect(find.text('Custom Right Pane'), findsOneWidget);

      // Trigger chat message to exercise _onChatUpdate
      await controller.sendMessage('Split chat test');
      await tester.pumpAndSettle();
    });
  });

  group('AdkWorkflowGraphView 100% tests', () {
    testWidgets('AdkGraphNode const, AdkGraphEdge const, edge status colors, and labeled edge tile', (WidgetTester tester) async {
      const node1 = AdkGraphNode(id: 'n1', label: 'Start', status: AdkGraphNodeStatus.completed);
      const node2 = AdkGraphNode(id: 'n2', label: 'Failed', status: AdkGraphNodeStatus.failed);
      const node3 = AdkGraphNode(id: 'n3', label: 'Skipped', status: AdkGraphNodeStatus.skipped);
      const edge = AdkGraphEdge(fromId: 'n1', toId: 'n2', label: 'transition_label');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkWorkflowGraphView(
              nodes: const [node1, node2, node3],
              edges: const [edge],
              failedColor: Colors.purple,
              skippedColor: Colors.brown,
            ),
          ),
        ),
      );

      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('transition_label'), findsOneWidget);

      // Tap node
      await tester.tap(find.text('Start'));
      await tester.pump();
    });
  });

  group('AdkSessionController 100% tests', () {
    test('isLoading getter and loadAllSessions with valid json, sorting, and fallback', () async {
      final storage = AdkMemoryStorage();
      final now = DateTime.now();

      storage.write(
        'adk_session_app_user_s1',
        jsonEncode({
          'id': 's1',
          'title': 'Session 1',
          'events': [1, 2],
          'updatedAt': now.subtract(const Duration(minutes: 10)).toIso8601String(),
        }),
      );
      storage.write(
        'adk_session_app_user_s2',
        jsonEncode({
          'id': 's2',
          'title': 'Session 2',
          'events': [1],
          'updatedAt': now.toIso8601String(),
        }),
      );
      storage.write('adk_session_app_user_empty', '');

      final controller = AdkSessionController(
        storage: storage,
        appName: 'app',
        userId: 'user',
      );

      expect(controller.isLoading, false);
      await controller.loadAllSessions();
      expect(controller.sessions.length, 2);
      // s2 is newer, so it should be first
      expect(controller.sessions.first.id, 's2');
      expect(controller.activeSessionId, 's2');
    });
  });

  group('AdkChatController 100% tests', () {
    test('stream onError handling and codeExecutionResult parsing via loadSession', () async {
      final agent = _CoverageMockAgent();
      final streamCtrl = StreamController<adk.Event>();
      final runner = _CoverageMockRunner(
        agent: agent,
        streamFactory: () => streamCtrl.stream,
      );

      final controller = AdkChatController(
        agent: agent,
        runner: runner,
      );

      // Send message and inject stream error
      final future = controller.sendMessage('Test stream error');
      streamCtrl.addError(Exception('Fatal Network Error'));
      await streamCtrl.close();
      await future;

      expect(controller.currentError, contains('Fatal Network Error'));
      expect(controller.messages.any((m) => m.errorMessage?.contains('Fatal Network Error') == true), true);

      // Test loadSession with code execution result and non-map fallbacks
      final sessionService = adk.InMemorySessionService();
      final session = await sessionService.createSession(
        appName: 'test_app',
        userId: 'test_user',
        sessionId: 'sess_code_exec',
      );
      await sessionService.appendEvent(
        session: session,
        event: adk.Event(
          id: 'exec_evt_1',
          invocationId: 'inv_1',
          author: 'CodeAgent',
          timestamp: 1700000000.0,
          content: adk.Content(
            role: 'model',
            parts: [
              adk.Part(
                executableCode: 'non_map_code',
                codeExecutionResult: 'non_map_output',
              ),
            ],
          ),
        ),
      );

      final historyController = AdkChatController(
        agent: agent,
        appName: 'test_app',
        userId: 'test_user',
        sessionId: 'sess_code_exec',
        sessionService: sessionService,
      );
      await historyController.loadSession();
      expect(historyController.messages.any((m) => m.id == 'hist_exec_exec_evt_1'), true);
    });
  });

  group('AdkSmartFormView and Controller 100% tests', () {
    testWidgets('AdkFormField.copyWith, external controller, chat update field populating, and builders', (WidgetTester tester) async {
      const field = AdkFormField(key: 'name', label: 'Name', isRequired: true);
      final updatedField = field.copyWith(value: 'Alice');
      expect(updatedField.value, 'Alice');

      final formCtrl = AdkSmartFormController(
        initialFields: const [
          AdkFormField(key: 'username', label: 'Username'),
          AdkFormField(key: 'category', label: 'Category'),
        ],
      );

      expect(formCtrl.isSubmitting, false);

      final agent = _CoverageMockAgent();
      final sessionService = adk.InMemorySessionService();
      final session = await sessionService.createSession(
        appName: 'form_app',
        userId: 'form_user',
        sessionId: 'form_sess',
      );
      final chatCtrl = AdkChatController(
        agent: agent,
        appName: 'form_app',
        userId: 'form_user',
        sessionId: 'form_sess',
        sessionService: sessionService,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkSmartFormView(
              agent: agent,
              controller: chatCtrl,
              fields: const [
                AdkFormField(key: 'username', label: 'Username', isRequired: false),
                AdkFormField(key: 'category', label: 'Category', isRequired: false),
              ],
              onSubmit: (_) {},
              submitButtonBuilder: (ctx, ready, submit) => ElevatedButton(
                onPressed: ready ? submit : null,
                child: const Text('Custom Submit Btn'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Custom Submit Btn'), findsOneWidget);

      // Append a tool event and loadSession to trigger _onChatUpdate
      await sessionService.appendEvent(
        session: session,
        event: adk.Event(
          id: 'evt_fill',
          invocationId: 'inv_1',
          author: 'agent',
          content: adk.Content(
            role: 'model',
            parts: [
              adk.Part(
                functionCall: adk.FunctionCall(
                  id: 'fc_1',
                  name: 'fill_form',
                  args: {'username': 'bob_user'},
                ),
              ),
            ],
          ),
        ),
      );
      await chatCtrl.loadSession();
      await tester.pump();
      expect(find.text('bob_user'), findsOneWidget);

      // Test formCardBuilder
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkSmartFormView(
              agent: agent,
              fields: const [AdkFormField(key: 'a', label: 'A'), AdkFormField(key: 'b', label: 'B')],
              onSubmit: (_) {},
              formCardBuilder: (ctx, fields, submit) => Text('Custom Form Card: ${fields.length}'),
            ),
          ),
        ),
      );
      expect(find.text('Custom Form Card: 2'), findsOneWidget);
    });
  });

  group('AdkCodeExecutionCard 100% tests', () {
    testWidgets('copy button, expand toggle, non-OK outcome styling, and error container', (WidgetTester tester) async {
      final exec = const AdkCodeExecution(
        language: 'python',
        code: 'import sys\nsys.exit(1)',
        outcome: 'OUTCOME_DEADLINE_EXCEEDED',
        output: 'Process timed out',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkCodeExecutionCard(execution: exec),
          ),
        ),
      );

      expect(find.text('OUTCOME_DEADLINE_EXCEEDED'), findsOneWidget);
      expect(find.text('Process timed out'), findsOneWidget);

      // Tap card header to toggle expansion
      await tester.tap(find.text('PYTHON'));
      await tester.pumpAndSettle();

      // Tap copy code button
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
    });
  });

  group('AdkChatView 100% tests', () {
    testWidgets('onSubmitted, emptyStateWidget, typingIndicatorBuilder, messageBubbleBuilder, suggestions onSelected, and onVoicePressed', (WidgetTester tester) async {
      final agent = _CoverageMockAgent();
      final controller = AdkChatController(agent: agent);
      bool voiceTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkChatView(
              controller: controller,
              emptyStateWidget: const Text('My Custom Empty Chat'),
              onVoicePressed: () => voiceTapped = true,
              suggestions: const ['Ask about weather'],
            ),
          ),
        ),
      );

      expect(find.text('My Custom Empty Chat'), findsOneWidget);
      expect(find.text('Ask about weather'), findsOneWidget);

      // Tap voice button
      await tester.tap(find.byIcon(Icons.mic_outlined));
      await tester.pump();
      expect(voiceTapped, true);

      // Tap prompt suggestion
      await tester.tap(find.text('Ask about weather'));
      await tester.pumpAndSettle();

      // Send via TextField onSubmitted
      await tester.enterText(find.byType(TextField), 'Enter submitted message');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      // Test custom builders
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkChatView(
              controller: controller,
              typingIndicatorBuilder: (ctx) => const Text('Custom Typing...'),
              messageBubbleBuilder: (ctx, msg) => Text('Custom Bubble: ${msg.text}'),
            ),
          ),
        ),
      );

      expect(find.text('Custom Bubble: Ask about weather'), findsOneWidget);
    });
  });

  group('AdkMessageBubble 100% tests', () {
    testWidgets('fgColor, typing indicator, audio attachment, and copy text', (WidgetTester tester) async {
      final audioMsg = AdkChatMessage.model(
        id: 'audio_1',
        text: 'Listen to this track',
        attachments: [
          const AdkAttachment(name: 'speech.mp3', mimeType: 'audio/mpeg'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AdkMessageBubble(message: audioMsg),
                AdkMessageBubble(
                  message: AdkChatMessage.model(
                    id: 'partial_1',
                    text: 'Thinking',
                    isPartial: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Listen to this track'), findsOneWidget);
      expect(find.byIcon(Icons.audiotrack), findsOneWidget);
      expect(find.byType(AdkTypingIndicator), findsOneWidget);
    });
  });

  group('AdkToolCallCard and ToolInspectorView 100% tests', () {
    testWidgets('tool call running spinner, error text, schema formatting, and empty tools state', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AdkToolCallCard(toolName: 'search_database', isRunning: true),
                AdkToolCallCard(
                  toolName: 'execute_command',
                  errorMessage: 'Disk access denied',
                  initiallyExpanded: true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Error: Disk access denied'), findsOneWidget);

      // ToolInspectorView empty state
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkToolInspectorView(tools: []),
          ),
        ),
      );
      expect(find.text('No tools registered to this agent.'), findsOneWidget);
    });
  });

  group('AdkReasoningExpander 100% tests', () {
    testWidgets('copyThought, customHeaderBuilder, and customBodyBuilder', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkReasoningExpander(
              thought: 'Deep chain-of-thought analysis',
              customHeaderBuilder: (ctx, expanded, toggle) => TextButton(
                onPressed: toggle,
                child: Text('Thought: $expanded'),
              ),
              customBodyBuilder: (ctx, thought) => Text('Body: $thought'),
            ),
          ),
        ),
      );

      expect(find.text('Thought: false'), findsOneWidget);

      // Toggle expand
      await tester.tap(find.text('Thought: false'));
      await tester.pumpAndSettle();
      expect(find.text('Body: Deep chain-of-thought analysis'), findsOneWidget);

      // Test default with copy button
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkReasoningExpander(thought: 'Standard thought'),
          ),
        ),
      );

      await tester.tap(find.text('Thinking Process'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.copy), findsOneWidget);
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
    });
  });

  group('AdkSessionDrawer and StructuredDataView 100% tests', () {
    testWidgets('custom headerWidget, empty sessions state, and lastMessagePreview', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkSessionDrawer(
              sessions: const [],
              activeSessionId: 'none',
              onNewSession: () {},
              headerWidget: const Text('My Session Drawer Header'),
              onSessionSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('My Session Drawer Header'), findsOneWidget);
      expect(find.text('No previous sessions'), findsOneWidget);

      // With sessions and lastMessagePreview
      final session = AdkSessionInfo(
        id: 's_prev',
        title: 'Project Planning',
        lastMessagePreview: 'We need to deploy v2',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkSessionDrawer(
              sessions: [session],
              activeSessionId: 's_prev',
              onNewSession: () {},
              onSessionSelected: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('We need to deploy v2'), findsOneWidget);
    });

    testWidgets('AdkStructuredDataView with valid/invalid JSON string, copy button, and null title border', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkStructuredDataView(
              data: '{"key": "value"}',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.copy), findsOneWidget);
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();

      // Invalid json string
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkStructuredDataView(
              data: '{invalid json',
            ),
          ),
        ),
      );
      expect(find.text('{invalid json'), findsOneWidget);
    });
  });

  group('AdkVoiceWidgets, Controller, and CascadeLiveBar 100% tests', () {
    testWidgets('AdkAudioWaveVisualizer didUpdateWidget, mic button colors, and controller simulation tick', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkAudioWaveVisualizer(isActive: false),
          ),
        ),
      );

      // Trigger didUpdateWidget to active
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkAudioWaveVisualizer(isActive: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // AdkVoiceMicButton custom inactiveColor
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkVoiceMicButton(
              isListening: false,
              inactiveColor: Colors.teal,
              onPressed: () {},
            ),
          ),
        ),
      );
      expect(find.byType(AdkVoiceMicButton), findsOneWidget);

      // Voice controller timer simulation tick
      final voiceCtrl = AdkVoiceController();
      voiceCtrl.startListening();
      expect(voiceCtrl.state.status, AdkVoiceStatus.listening);
      // Wait for timer tick
      await tester.pump(const Duration(milliseconds: 150));
      voiceCtrl.stopListening();
      voiceCtrl.dispose();
    });

    testWidgets('AdkCascadeLiveBar didUpdateWidget isBargeIn and inactive state color', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkCascadeLiveBar(
              statusText: 'Listening...',
              isListening: false,
              isBargeIn: false,
            ),
          ),
        ),
      );

      // Trigger didUpdateWidget isBargeIn true
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkCascadeLiveBar(
              statusText: 'Interrupted!',
              isListening: false,
              isBargeIn: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('AdkTheme and BottomSheetChat 100% tests', () {
    testWidgets('AdkTheme copyWith, maybeOf, updateShouldNotify, and AdkBottomSheetChat header/subtitle/pop', (WidgetTester tester) async {
      final themeData = const AdkChatThemeData().copyWith(
        userBubbleColor: Colors.blue,
        showAvatars: false,
      );
      expect(themeData.userBubbleColor, Colors.blue);
      expect(themeData.showAvatars, false);

      AdkChatThemeData? extractedTheme;
      await tester.pumpWidget(
        AdkTheme(
          data: themeData,
          child: Builder(
            builder: (ctx) {
              extractedTheme = AdkTheme.maybeOf(ctx);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(extractedTheme?.userBubbleColor, Colors.blue);

      // AdkBottomSheetChat custom header, subtitle, and pop button
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: ctx,
                    builder: (_) => AdkBottomSheetChat(
                      agent: _CoverageMockAgent(),
                      title: 'Assistant',
                      subtitle: 'Always here to help',
                    ),
                  );
                },
                child: const Text('Open Bottom Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Bottom Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Always here to help'), findsOneWidget);

      // Tap close button in header
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Always here to help'), findsNothing);
    });
  });

  group('Models, Storage, and ArtifactViewer 100% tests', () {
    test('copyWith on metadata, session, token, workflow step, and tool call info', () {
      final metrics = const AdkAgentMetrics(totalInvocations: 10).copyWith(errorCount: 5);
      expect(metrics.errorCount, 5);

      final sess = AdkSessionInfo(id: 's', title: 'Old').copyWith(title: 'New');
      expect(sess.title, 'New');

      final tokens = const AdkTokenUsage().copyWith(totalTokens: 500);
      expect(tokens.totalTokens, 500);

      final step = const AdkWorkflowStep(id: 'st', label: 'Step').copyWith(status: AdkStepStatus.running);
      expect(step.status, AdkStepStatus.running);

      final call = const AdkToolCallInfo(callId: 'tc', toolName: 'tool').copyWith(
        status: AdkToolStatus.error,
        errorMessage: 'failed',
      );
      expect(call.status, AdkToolStatus.error);
      expect(call.errorMessage, 'failed');

      // AdkAttachment equality
      const attA = AdkAttachment(name: 'f.png', mimeType: 'image/png', uri: 'u1', sizeBytes: 100);
      const attB = AdkAttachment(name: 'f.png', mimeType: 'image/png', uri: 'u1', sizeBytes: 100);
      const attC = AdkAttachment(name: 'f2.png', mimeType: 'image/png', uri: 'u1', sizeBytes: 100);
      expect(attA == attB, true);
      expect(attA == attC, false);

      // AdkGroundingSource & AdkGroundingInfo equality
      const srcA = AdkGroundingSource(title: 'T1', uri: 'http://a.com');
      const srcB = AdkGroundingSource(title: 'T1', uri: 'http://a.com');
      const srcC = AdkGroundingSource(title: 'T2', uri: 'http://b.com');
      expect(srcA == srcB, true);
      expect(srcA == srcC, false);

      const grndA = AdkGroundingInfo(searchQueries: ['q1'], sources: [srcA]);
      const grndB = AdkGroundingInfo(searchQueries: ['q1'], sources: [srcA]);
      const grndC = AdkGroundingInfo(searchQueries: ['q2'], sources: [srcA]);
      expect(grndA == grndB, true);
      expect(grndA == grndC, false);
    });

    test('AdkStorageSessionService custom delegates, null sessionId, and empty userId prefix', () async {
      bool deleted = false;
      final custom = AdkStorageSessionService.custom(
        read: (k) => null,
        write: (k, v) {},
        delete: (k) => deleted = true,
        getKeys: ({prefix = ''}) => ['session_1'],
      );

      await custom.deleteSession(appName: 'app', userId: 'u', sessionId: 's');
      expect(deleted, true);

      // createSession with null sessionId and empty userId
      final inMem = AdkStorageSessionService.inMemory();
      final newSess = await inMem.createSession(appName: 'app', userId: '');
      expect(newSess.id.startsWith('session_'), true);
    });

    testWidgets('AdkArtifactViewer table check (.csv and .xlsx) and MB formatting', (WidgetTester tester) async {
      const csvItem = AdkArtifactItem(
        name: 'data.csv',
        sizeBytes: 5 * 1024 * 1024, // 5 MB
        content: 'col1,col2\nval1,val2',
      );
      expect(csvItem.isCodeOrJson, false);
      expect(csvItem.isMarkdown, false);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkArtifactCard(artifact: csvItem),
          ),
        ),
      );
      expect(find.text('5.0 MB'), findsOneWidget);
    });
  });

  group('WorkflowController, ClassifierCard, and HITL/Interrupt 100% tests', () {
    test('AdkWorkflowController currentStepIndex and error handling', () async {
      final agent = _CoverageMockAgent();
      final ctrl = AdkWorkflowController(
        workflowAgent: agent,
        runnerFactory: (_) => throw Exception('Workflow Runner Creation Failed'),
      );

      expect(ctrl.currentStepIndex, isNull);
      await ctrl.execute();
      expect(ctrl.currentError, contains('Workflow Runner Creation Failed'));
      expect(ctrl.isRunning, false);
    });

    testWidgets('AdkClassifierCard confidenceColorBuilder, score thresholds, and probabilityBarColorBuilder', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const AdkClassifierCard(
                    selectedRoute: 'route_mid',
                    confidence: 0.65,
                    probabilities: {'route_mid': 0.65, 'other': 0.35},
                  ),
                  const AdkClassifierCard(
                    selectedRoute: 'route_low',
                    confidence: 0.2,
                    probabilities: {'route_low': 0.2, 'other': 0.8},
                  ),
                  AdkClassifierCard(
                    selectedRoute: 'route_custom',
                    confidence: 0.9,
                    probabilities: const {'route_custom': 0.9},
                    confidenceColorBuilder: (ctx, sc) => Colors.cyan,
                    probabilityBarColorBuilder: (ctx, k, p, sel) => Colors.indigo,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('route_mid'), findsWidgets);
      expect(find.text('route_low'), findsWidgets);
      expect(find.text('route_custom'), findsWidgets);
    });

    testWidgets('AdkHumanInTheLoopCard isSubmitting spinner and Interrupt onResume', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkHumanInTheLoopCard(
              toolName: 'sensitive_tool',
              arguments: {'unencodable': Object()},
              isProcessing: true,
              onApprove: () {},
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // AdkInterruptCard onResume callback
      String? resumedVal;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkInterruptCard(
              toolName: 'exec_tool',
              arguments: {'unencodable': Object()},
              requiresInput: true,
              onResume: (val) => resumedVal = val,
              actionsBuilder: (context, onResume, onCancel, isProcessing) => ElevatedButton(
                onPressed: () => onResume?.call('custom_input'),
                child: const Text('Custom Resume'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Custom Resume'));
      await tester.pump();
      expect(resumedVal, 'custom_input');
    });
  });

  group('PromptSuggestions, PersonaSelector, Badges, and Dialogs 100% tests', () {
    testWidgets('AdkPromptSuggestionsBar custom colors and icons', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkPromptSuggestionsBar(
              suggestions: const ['Idea 1', 'Idea 2'],
              icon: Icons.lightbulb_outline,
              onSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.lightbulb_outline), findsNWidgets(2));
      expect(find.text('Idea 1'), findsOneWidget);
    });

    testWidgets('AdkAgentPersonaSelector cardBuilder and default tap', (WidgetTester tester) async {
      const persona = AdkPersona(id: 'p1', name: 'Analyst', description: 'Data analyst');
      AdkPersona? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentPersonaSelector(
              personas: const [persona],
              onPersonaSelected: (p) => selected = p,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Analyst'));
      await tester.pump();
      expect(selected?.id, 'p1');

      // Custom cardBuilder
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentPersonaSelector(
              personas: const [persona],
              onPersonaSelected: (_) {},
              cardBuilder: (ctx, p, sel, onSel) => ElevatedButton(
                onPressed: onSel,
                child: Text('Custom: ${p.name}'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Custom: Analyst'), findsOneWidget);
    });

    testWidgets('const widgets, confirmation dialog cancel, grounding uri fallback', (WidgetTester tester) async {
      const badge1 = AdkAgentHierarchyBadge(agentPath: ['Coordinator', 'Worker']);
      const badge2 = AdkTokenUsageBadge(promptTokens: 50, candidatesTokens: 50);
      const escalationCard = AdkEscalationCard(
        advisorModel: 'gemini-pro',
        escalationReason: 'complex query',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                badge1,
                badge2,
                escalationCard,
                AdkGroundingSourcesBar(
                  grounding: const AdkGroundingInfo(
                    sources: [
                      AdkGroundingSource(title: '', uri: 'https://grounding.example.com'),
                    ],
                  ),
                ),
                AdkEscalationCard(
                  advisorModel: 'gemini-pro',
                  escalationReason: 'complex problem',
                  initiallyExpanded: true,
                  headerBuilder: (ctx, expanded, toggle) => const Text('Custom Escalation Header'),
                  contentBuilder: (ctx) => const Text('Custom Escalation Content'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Worker'), findsOneWidget);
      expect(find.text('https://grounding.example.com'), findsOneWidget);
      expect(find.text('Custom Escalation Header'), findsOneWidget);
      expect(find.text('Custom Escalation Content'), findsOneWidget);

      // AdkConfirmationBanner.showAsDialog cancel button
      bool? dialogResult;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  dialogResult = await AdkConfirmationBanner.showAsDialog(
                    ctx,
                    title: 'Confirm',
                    description: 'Are you sure?',
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deny'));
      await tester.pumpAndSettle();
      expect(dialogResult, false);
    });

    testWidgets('AdkInlineAssistantBar loading indicator when action is executing', (WidgetTester tester) async {
      final agent = _CoverageMockAgent();
      final streamCtrl = StreamController<adk.Event>();
      final runner = _CoverageMockRunner(
        agent: agent,
        streamFactory: () => streamCtrl.stream,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkInlineAssistantBar(
              agent: agent,
              currentText: 'Sample text to summarize',
              runnerFactory: (_) => runner,
              actions: const [
                AdkInlineAction(label: 'Summarize', promptPrefix: 'Summarize:'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Summarize'), findsOneWidget);

      // Tap action
      await tester.tap(find.text('Summarize'));
      await tester.pump();

      // Verify CircularProgressIndicator is rendered on the active action chip
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Finish execution
      streamCtrl.add(
        adk.Event(
          id: 'e_fin',
          invocationId: 'i_fin',
          author: 'mock_agent',
          content: adk.Content.modelText('Summary complete'),
        ),
      );
      await streamCtrl.close();
      await tester.pumpAndSettle();
    });
  });

  group('Final 100% gap closure tests', () {
    testWidgets('AdkChatController handles stream onError callback', (tester) async {
      final streamCtrl = StreamController<adk.Event>();
      final agent = _CoverageMockAgent();
      final runner = _CoverageMockRunner(agent: agent, streamFactory: () => streamCtrl.stream);
      final controller = AdkChatController(agent: agent, runner: runner);

      final future = controller.sendMessage('test stream failure');
      await tester.pump();

      streamCtrl.add(
        adk.Event(
          id: 'chunk_1',
          invocationId: 'inv_1',
          author: 'mock_agent',
          content: adk.Content.modelText('initial chunk'),
        ),
      );
      await tester.pump();

      streamCtrl.addError('test stream error message');
      await streamCtrl.close();
      await future;
      await tester.pumpAndSettle();

      expect(
        controller.messages.any(
          (m) => m.text == 'Stream error' || (m.errorMessage?.contains('test stream error message') ?? false),
        ),
        isTrue,
      );
    });

    test('AdkSessionController handles null updatedAt fallback', () async {
      final storage = AdkMemoryStorage();
      storage.write(
        'adk_session_app_user_s_no_updated',
        jsonEncode(<String, dynamic>{
          'id': 's_no_updated',
          'title': 'Session Without Updated At',
          'updatedAt': null,
          'events': <dynamic>[],
        }),
      );
      final controller = AdkSessionController(storage: storage, appName: 'app', userId: 'user');
      await controller.loadAllSessions();
      expect(controller.sessions.any((s) => s.id == 's_no_updated'), isTrue);
    });

    test('AdkAgentMetrics copyWith errorCount', () {
      const metrics = AdkAgentMetrics(totalInvocations: 1, totalTokens: 10, errorCount: 0);
      expect(metrics.copyWith().errorCount, 0);
      final updated = metrics.copyWith(errorCount: 3);
      expect(updated.errorCount, 3);
    });

    test('AdkAttachment equality branches', () {
      const a1 = AdkAttachment(name: 'doc', mimeType: 'text/plain', uri: 'u1', sizeBytes: 100);
      const a2 = AdkAttachment(name: 'doc', mimeType: 'image/png', uri: 'u1', sizeBytes: 100);
      const a3 = AdkAttachment(name: 'doc', mimeType: 'text/plain', uri: 'u2', sizeBytes: 100);
      const a4 = AdkAttachment(name: 'doc', mimeType: 'text/plain', uri: 'u1', sizeBytes: 200);
      const a5 = AdkAttachment(name: 'doc', mimeType: 'text/plain', uri: 'u1', sizeBytes: 100);

      expect(a1 == a2, isFalse);
      expect(a1 == a3, isFalse);
      expect(a1 == a4, isFalse);
      expect(a1 == a5, isTrue);
    });

    test('AdkGroundingSource and AdkGroundingInfo equality branches', () {
      const s1 = AdkGroundingSource(title: 'Source', uri: 'uri1');
      const s2 = AdkGroundingSource(title: 'Source', uri: 'uri2');
      expect(s1 == s2, isFalse);

      const g1 = AdkGroundingInfo(searchQueries: ['q'], sources: [s1]);
      const g2 = AdkGroundingInfo(searchQueries: ['q'], sources: [s2]);
      expect(g1 == g2, isFalse);
    });

    test('AdkSessionInfo, AdkTokenUsage, AdkToolCallInfo, and AdkWorkflowStep copyWith fallbacks', () {
      final now = DateTime.now();
      final session = AdkSessionInfo(id: 's', title: 'T', createdAt: now, updatedAt: now);
      expect(session.copyWith().title, 'T');
      expect(session.copyWith(title: 'T2').title, 'T2');

      const usage = AdkTokenUsage(promptTokens: 1, completionTokens: 2, totalTokens: 3);
      expect(usage.copyWith().totalTokens, 3);
      expect(usage.copyWith(totalTokens: 10).totalTokens, 10);

      const toolCall = AdkToolCallInfo(callId: 'c1', toolName: 't1', status: AdkToolStatus.success, errorMessage: 'none');
      expect(toolCall.copyWith().status, AdkToolStatus.success);
      expect(toolCall.copyWith().errorMessage, 'none');
      final updatedCall = toolCall.copyWith(status: AdkToolStatus.error, errorMessage: 'err');
      expect(updatedCall.status, AdkToolStatus.error);
      expect(updatedCall.errorMessage, 'err');

      const step = AdkWorkflowStep(id: 'step1', label: 'Step 1');
      expect(step.copyWith().label, 'Step 1');
      expect(step.copyWith(output: {'k': 'v'}).output, {'k': 'v'});
    });

    test('AdkStorageSessionService custom getKeys and null userId listSessions', () async {
      final custom = AdkStorageSessionService.custom(
        read: (k) async => null,
        write: (k, v) async {},
        delete: (k) async {},
        getKeys: ({prefix = ''}) async => ['key1', 'key2'],
      );
      final keys = await custom.storage.getKeys(prefix: 'pref');
      expect(keys, ['key1', 'key2']);

      final sessions = await custom.listSessions(appName: 'test_app', userId: null);
      expect(sessions.sessions, isEmpty);
    });

    test('AdkChatThemeData copyWith userBubbleColor and showAvatars', () {
      const theme = AdkChatThemeData();
      expect(theme.copyWith().userBubbleColor, isNull);
      expect(theme.copyWith().showAvatars, isFalse);
      final updated = theme.copyWith(userBubbleColor: Colors.cyan, showAvatars: true);
      expect(updated.userBubbleColor, Colors.cyan);
      expect(updated.showAvatars, isTrue);
    });

    test('AdkFormatters and AdkEventStreamUtils edge branches', () {
      expect(AdkFormatters.formatJson(_Unencodable()), 'UnencodableObject');

      final usageEvt1 = adk.Event(
        id: 'u1',
        invocationId: 'i1',
        author: 'a',
        usageMetadata: {'prompt_token_count': 10, 'candidates_token_count': 20},
      );
      final usageFromMap = AdkEventStreamUtils.extractTokenUsage(usageEvt1);
      expect(usageFromMap?.totalTokens, 30);

      final usageEvt2 = adk.Event(
        id: 'u2',
        invocationId: 'i2',
        author: 'a',
        usageMetadata: _CamelCaseUsageObj(),
      );
      final usageFromObj = AdkEventStreamUtils.extractTokenUsage(usageEvt2);
      expect(usageFromObj?.promptTokens, 15);
      expect(usageFromObj?.completionTokens, 25);
      expect(usageFromObj?.totalTokens, 40);

      final usageEvtDual = adk.Event(
        id: 'u_dual',
        invocationId: 'i_dual',
        author: 'a',
        usageMetadata: _DualUsageObj(),
      );
      final usageFromDual = AdkEventStreamUtils.extractTokenUsage(usageEvtDual);
      expect(usageFromDual?.promptTokens, 10);
      expect(usageFromDual?.completionTokens, 20);
      expect(usageFromDual?.totalTokens, 30);

      final brokenUsageEvt = adk.Event(
        id: 'u3',
        invocationId: 'i3',
        author: 'a',
        usageMetadata: _Unencodable(),
      );
      expect(AdkEventStreamUtils.extractTokenUsage(brokenUsageEvt), isNull);

      final consultEvt = adk.Event(
        id: 'e_esc',
        invocationId: 'inv_esc',
        author: 'system',
        customMetadata: <String, dynamic>{'escalated': true},
      );
      expect(AdkEventStreamUtils.isModelConsultEvent(consultEvt), isTrue);
    });

    testWidgets('AdkAgentHierarchyBadge, AdkTokenUsageBadge, AdkArtifactItem, and AdkGraphNode runtime constructors', (tester) async {
      final badge = AdkAgentHierarchyBadge(agentPath: const ['root', 'sub']);
      expect(badge.agentPath, const ['root', 'sub']);

      final tokenBadge = AdkTokenUsageBadge(promptTokens: 5, candidatesTokens: 10);
      expect(tokenBadge.promptTokens, 5);

      final artifact = AdkArtifactItem(name: 'art_1', content: 'content_1');
      expect(artifact.name, 'art_1');

      final node = AdkGraphNode(id: 'gn_1', label: 'Graph Node 1');
      expect(node.id, 'gn_1');
    });

    testWidgets('AdkAgentLoggerView auto-scroll, unencodable payload catch, and error category', (tester) async {
      final logsList = <AdkAgentLogEntry>[
        AdkAgentLogEntry(
          id: 'l1',
          timestamp: DateTime.now(),
          agentName: 'agent',
          category: AdkLogCategory.error,
          title: 'Error Log',
          payload: _Unencodable(),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: _StatefulLoggerTestHarness(initialLogs: logsList),
            ),
          ),
        ),
      );

      expect(find.text('Error Log'), findsOneWidget);

      // Tap the log tile to expand and format payload (triggers catch block)
      await tester.tap(find.text('Error Log'));
      await tester.pumpAndSettle();
      expect(find.text('UnencodableObject'), findsOneWidget);

      // Trigger didUpdateWidget auto-scroll
      await tester.tap(find.text('Add More Logs'));
      await tester.pumpAndSettle();
    });

    testWidgets('AdkAgentManagementView filter chips, custom card builder callbacks, error status and sub-agents badge', (tester) async {
      final controller = AdkAgentManagerController();
      final llm1 = adk.LlmAgent(
        name: 'a1',
        model: 'gemini-1.5',
        subAgents: [
          adk.LlmAgent(name: 's1', model: 'gemini-1.5'),
          adk.LlmAgent(name: 's2', model: 'gemini-1.5'),
          adk.LlmAgent(name: 's3', model: 'gemini-1.5'),
        ],
      );
      final llm2 = adk.LlmAgent(name: 'a2', model: 'gemini-1.5');

      controller.registerAgent(llm1, name: 'Agent 1', tags: const ['prod', 'finance']);
      controller.registerAgent(llm2, name: 'Agent 2', tags: const ['dev']);
      controller.setAgentStatus('a1', AdkAgentStatus.error);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentManagementView(controller: controller),
          ),
        ),
      );

      expect(find.text('3 Sub-Agents'), findsOneWidget);

      // Tap tag chip 'prod'
      await tester.tap(find.text('prod'));
      await tester.pumpAndSettle();
      expect(controller.selectedTag, 'prod');

      // Tap 'All' chip
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(controller.selectedTag, isNull);

      // Now test custom agentCardBuilder
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentManagementView(
              controller: controller,
              agentCardBuilder: (ctx, agent, onToggle, onInspect) {
                return ElevatedButton(
                  onPressed: () {
                    onToggle(true);
                    onInspect();
                  },
                  child: Text('Card: ${agent.name}'),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Card: Agent 1'), findsOneWidget);
      await tester.tap(find.text('Card: Agent 1'));
      await tester.pumpAndSettle();
    });

    testWidgets('AdkAgentPersonaSelector cardBuilder onSelect in grid and horizontalList', (tester) async {
      const persona = AdkPersona(id: 'p1', name: 'Tester', avatarUrl: 'url', description: 'test');
      AdkPersona? selected;

      // Grid
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentPersonaSelector(
              personas: const [persona],
              isGrid: true,
              onPersonaSelected: (p) => selected = p,
              cardBuilder: (ctx, p, isSel, onSel) {
                return ElevatedButton(
                  onPressed: onSel,
                  child: Text('GridCard: ${p.name}'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('GridCard: Tester'));
      await tester.pumpAndSettle();
      expect(selected?.id, 'p1');

      // Horizontal list
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentPersonaSelector(
              personas: const [persona],
              isGrid: false,
              onPersonaSelected: (p) => selected = p,
              cardBuilder: (ctx, p, isSel, onSel) {
                return ElevatedButton(
                  onPressed: onSel,
                  child: Text('HListCard: ${p.name}'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('HListCard: Tester'));
      await tester.pumpAndSettle();
      expect(selected?.id, 'p1');
    });

    testWidgets('AdkArtifactViewer copy action and delayed reset', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async => null,
      );
      final item = AdkArtifactItem(name: 'doc.md', content: 'Sample artifact text');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkArtifactViewer(artifact: item),
          ),
        ),
      );

      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.copy_rounded));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('showAdkChatBottomSheet with custom header', (tester) async {
      final agent = _CoverageMockAgent();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showAdkChatBottomSheet(
                    context: ctx,
                    agent: agent,
                    header: const Text('Custom Header Banner'),
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();
      expect(find.text('Custom Header Banner'), findsOneWidget);
    });

    testWidgets('AdkLiveBargeInIndicator didUpdateWidget transitions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkLiveBargeInIndicator(isBargeIn: false),
          ),
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkLiveBargeInIndicator(isBargeIn: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkLiveBargeInIndicator(isBargeIn: false),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('AdkChatView custom typingIndicatorBuilder', (tester) async {
      final agent = _MockAgentNeverResponds();
      final controller = AdkChatController(agent: agent);
      controller.addMessageForTesting(AdkChatMessage.user(id: 'u1', text: 'Hi'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _StatefulChatViewLoadingHarness(controller: controller),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Custom Typing Indicator Active'), findsOneWidget);
    });

    testWidgets('AdkCodeExecutionCard copy code and delayed reset', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async => null,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkCodeExecutionCard(
              execution: AdkCodeExecution(
                language: 'python',
                code: 'print(42)',
                output: '42',
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.copy), findsOneWidget);
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('AdkDevStudioView tool events, args, and clear logs', (tester) async {
      final agent = _CoverageMockAgent();
      final chatController = AdkChatController(agent: agent);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkDevStudioView(agent: agent, controller: chatController),
          ),
        ),
      );

      // Add tool message with args and empty text
      chatController.addMessageForTesting(
        AdkChatMessage.tool(
          id: 't_dev_1',
          text: '',
          toolName: 'calculator',
          toolArgs: <String, dynamic>{'op': 'add'},
        ),
      );
      chatController.addMessageForTesting(
        AdkChatMessage.system(
          id: 'sys_dev_1',
          text: 'System alert in DevStudio',
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Tab 2 (Live Logger)
      await tester.tap(find.text('Live Logger'));
      await tester.pumpAndSettle();

      expect(find.text('Tool: calculator'), findsOneWidget);

      // Clear logs via onClearLogs on the AdkAgentLoggerView directly
      final loggerView = tester.widget<AdkAgentLoggerView>(find.byType(AdkAgentLoggerView));
      loggerView.onClearLogs?.call();
      await tester.pumpAndSettle();
    });

    testWidgets('AdkMessageBubble bodyMedium null fallback, model avatar, and plain tool message', (tester) async {
      // 1. bodyMedium null fallback
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkMessageBubble(
              message: AdkChatMessage.user(id: 'u1', text: 'Hello No BodyMedium'),
            ),
          ),
        ),
      );
      expect(find.text('Hello No BodyMedium'), findsOneWidget);

      // 2. Model avatar
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkMessageBubble(
              message: AdkChatMessage.model(id: 'm1', text: 'Model with avatar'),
              theme: const AdkChatThemeData(showAvatars: true),
            ),
          ),
        ),
      );
      expect(find.text('Model with avatar'), findsOneWidget);

      // 3. Tool bubble without toolName
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkMessageBubble(
              message: AdkChatMessage(
                id: 't_plain',
                role: AdkMessageRole.tool,
                text: 'Plain Tool Output',
              ),
            ),
          ),
        ),
      );
      expect(find.text('Plain Tool Output'), findsOneWidget);
    });

    testWidgets('AdkPromptSuggestionsBar null theme colors fallback', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkPromptSuggestionsBar(
              suggestions: const ['Test Prompt'],
              onSelected: (_) {},
              theme: const AdkChatThemeData(
                suggestionBackgroundColor: null,
                suggestionTextColor: null,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Test Prompt'), findsOneWidget);
    });

    testWidgets('AdkReasoningExpander copy thought and delayed reset', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async => null,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkReasoningExpander(
              thought: 'Deep thought reasoning process',
              initialExpanded: true,
            ),
          ),
        ),
      );

      final copyBtn = find.byIcon(Icons.copy);
      expect(copyBtn, findsOneWidget);
      await tester.tap(copyBtn);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
    });

    test('AdkFormField copyWith value', () {
      const field = AdkFormField(key: 'name', label: 'Name', value: 'old');
      expect(field.copyWith().value, 'old');
      final updated = field.copyWith(value: 'new');
      expect(updated.value, 'new');
    });

    testWidgets('AdkSplitPaneView tool/system message logs and onClearLogs', (tester) async {
      final agent = _CoverageMockAgent();
      final controller = AdkChatController(agent: agent);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkSplitPaneView(
              agent: agent,
              controller: controller,
              showLogger: true,
            ),
          ),
        ),
      );

      controller.addMessageForTesting(
        AdkChatMessage.tool(
          id: 't_split',
          text: '',
          toolName: 'web_search',
          toolArgs: <String, dynamic>{'query': 'flutter'},
        ),
      );
      controller.addMessageForTesting(
        AdkChatMessage.system(
          id: 'sys_split',
          text: 'System alert message',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tool: web_search'), findsWidgets);
      expect(find.text('System alert message'), findsOneWidget);

      final loggerView = tester.widget<AdkAgentLoggerView>(find.byType(AdkAgentLoggerView));
      loggerView.onClearLogs?.call();
      await tester.pumpAndSettle();
    });

    testWidgets('AdkStructuredDataView unencodable data and showCard false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkStructuredDataView(
              data: _Unencodable(),
              showCard: false,
            ),
          ),
        ),
      );
      expect(find.text('UnencodableObject'), findsOneWidget);
    });

    testWidgets('AdkToolCallCard unencodable result catch', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkToolCallCard(
              toolName: 'complex_tool',
              toolResult: _Unencodable(),
              initiallyExpanded: true,
            ),
          ),
        ),
      );
      expect(find.text('UnencodableObject'), findsOneWidget);
    });

    testWidgets('AdkToolInspectorView unencodable schema catch', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkToolInspectorView(
              tools: [_MockNodeToolWithUnencodableSchema()],
            ),
          ),
        ),
      );
      await tester.tap(find.text('unencodable_node'));
      await tester.pumpAndSettle();
      expect(find.textContaining('UnencodableObject'), findsOneWidget);
    });

    testWidgets('AdkAudioWaveVisualizer isActive transitions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkAudioWaveVisualizer(isActive: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkAudioWaveVisualizer(isActive: false),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('AdkWorkflowGraphView vertical orientation with labeled edge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkWorkflowGraphView(
              orientation: Axis.vertical,
              nodes: [
                AdkGraphNode(id: 'v1', label: 'Step 1'),
                AdkGraphNode(id: 'v2', label: 'Step 2'),
              ],
              edges: const [
                AdkGraphEdge(fromId: 'v1', toId: 'v2', label: 'continue_flow'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Step 1'), findsOneWidget);
      expect(find.text('Step 2'), findsOneWidget);
      expect(find.text('continue_flow'), findsOneWidget);
    });
  });
}

class _Unencodable {
  @override
  String toString() => 'UnencodableObject';
  dynamic toJson() => throw const FormatException('Cannot encode');
}

class _CamelCaseUsageObj {
  int get promptTokenCount => 15;
  int get candidatesTokenCount => 25;
  int get totalTokenCount => 40;
}

class _DualUsageObj {
  int? get promptTokenCount => null;
  // ignore: non_constant_identifier_names
  int get prompt_token_count => 10;
  int? get candidatesTokenCount => null;
  // ignore: non_constant_identifier_names
  int get candidates_token_count => 20;
  int? get totalTokenCount => null;
  // ignore: non_constant_identifier_names
  int? get total_token_count => null;
}

class _MockNodeToolWithUnencodableSchema extends adk.NodeTool {
  _MockNodeToolWithUnencodableSchema()
      : super(
          node: adk.FunctionNode(
            name: 'unencodable_node',
            function: (ctx, input) => null,
          ),
          inputSchema: <String, dynamic>{'bad': _Unencodable()},
        );
}

class _MockAgentNeverResponds extends adk.BaseAgent {
  _MockAgentNeverResponds() : super(name: 'never', description: 'desc');

  @override
  Stream<adk.Event> runAsyncImpl(adk.InvocationContext context) {
    final comp = Completer<adk.Event>();
    return Stream.fromFuture(comp.future);
  }
}

class _StatefulLoggerTestHarness extends StatefulWidget {
  const _StatefulLoggerTestHarness({required this.initialLogs});
  final List<AdkAgentLogEntry> initialLogs;

  @override
  State<_StatefulLoggerTestHarness> createState() => _StatefulLoggerTestHarnessState();
}

class _StatefulLoggerTestHarnessState extends State<_StatefulLoggerTestHarness> {
  late List<AdkAgentLogEntry> logs;

  @override
  void initState() {
    super.initState();
    logs = List<AdkAgentLogEntry>.from(widget.initialLogs);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () {
            setState(() {
              final newLogs = List<AdkAgentLogEntry>.from(logs);
              for (int i = 0; i < 20; i++) {
                newLogs.add(
                  AdkAgentLogEntry(
                    id: 'scroll_$i',
                    timestamp: DateTime.now(),
                    agentName: 'agent',
                    category: AdkLogCategory.toolCall,
                    title: 'Scroll Log $i',
                  ),
                );
              }
              logs = newLogs;
            });
          },
          child: const Text('Add More Logs'),
        ),
        Expanded(
          child: AdkAgentLoggerView(logs: logs),
        ),
      ],
    );
  }
}

class _StatefulChatViewLoadingHarness extends StatefulWidget {
  const _StatefulChatViewLoadingHarness({required this.controller});
  final AdkChatController controller;

  @override
  State<_StatefulChatViewLoadingHarness> createState() => _StatefulChatViewLoadingHarnessState();
}

class _StatefulChatViewLoadingHarnessState extends State<_StatefulChatViewLoadingHarness> {
  @override
  void initState() {
    super.initState();
    widget.controller.sendMessage('trigger');
  }

  @override
  Widget build(BuildContext context) {
    return AdkChatView(
      controller: widget.controller,
      typingIndicatorBuilder: (ctx) => const Text('Custom Typing Indicator Active'),
    );
  }
}

class _FakeUsageObj {
  _FakeUsageObj({required this.prompt, required this.candidates, required this.total});
  final int prompt;
  final int candidates;
  final int total;

  int get promptTokenCount => prompt;
  int get candidatesTokenCount => candidates;
  int get totalTokenCount => total;
  // ignore: non_constant_identifier_names
  int get prompt_token_count => prompt;
  // ignore: non_constant_identifier_names
  int get candidates_token_count => candidates;
  // ignore: non_constant_identifier_names
  int get total_token_count => total;
}
