import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('New Parity Widgets Tests', () {
    testWidgets('AdkInterruptBanner renders tool name, reason and handles resume tap',
        (WidgetTester tester) async {
      bool resumed = false;
      bool dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkInterruptBanner(
              toolName: 'execute_payment',
              reason: 'Payment amount \$120 requires explicit approval.',
              onResume: () => resumed = true,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      expect(find.text('Action Required: execute_payment'), findsOneWidget);
      expect(
        find.text('Payment amount \$120 requires explicit approval.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Review & Resume'));
      await tester.pump();
      expect(resumed, isTrue);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(dismissed, isTrue);
    });

    testWidgets('AdkInterruptCard renders arguments and submits input on resume',
        (WidgetTester tester) async {
      String? submittedInput;
      bool cancelled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkInterruptCard(
              toolName: 'request_otp',
              interruptId: 'int-1234',
              arguments: const <String, dynamic>{'phone': '+15550199'},
              reason: 'Please enter the 6-digit OTP code sent to your phone.',
              requiresInput: true,
              inputPlaceholder: 'Enter OTP...',
              onResume: (String? val) => submittedInput = val,
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );

      expect(find.text('Tool Interrupted: request_otp'), findsOneWidget);
      expect(find.text('ID: int-1234'), findsOneWidget);
      expect(find.textContaining('+15550199'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '654321');
      await tester.pump();

      await tester.tap(find.text('Resume'));
      await tester.pump();
      expect(submittedInput, '654321');

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(cancelled, isTrue);
    });

    testWidgets('AdkCascadeLiveBar renders controls and displays barge-in indicator',
        (WidgetTester tester) async {
      bool micToggled = false;
      bool disconnected = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkCascadeLiveBar(
              isListening: true,
              isSpeaking: false,
              isBargeIn: true,
              partialTranscript: 'I would like to change my booking...',
              onMicToggle: () => micToggled = true,
              onDisconnect: () => disconnected = true,
            ),
          ),
        ),
      );

      expect(find.text('User speaking...'), findsOneWidget);
      expect(find.text('Agent Interrupted'), findsOneWidget);
      expect(find.text('I would like to change my booking...'), findsOneWidget);

      await tester.tap(find.byType(AdkVoiceMicButton));
      await tester.pump();
      expect(micToggled, isTrue);

      await tester.tap(find.byIcon(Icons.call_end_rounded));
      await tester.pump();
      expect(disconnected, isTrue);
    });

    testWidgets('AdkModelConsultBadge and AdkEscalationCard render consultation budget',
        (WidgetTester tester) async {
      bool badgeTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  AdkModelConsultBadge(
                    advisorModel: 'gemini-2.5-pro',
                    escalationReason: 'Complex spatial analysis',
                    turnCount: 2,
                    turnBudget: 3,
                    onTap: () => badgeTapped = true,
                  ),
                  const AdkEscalationCard(
                    advisorModel: 'gemini-2.5-pro',
                    escalationReason: 'Requires high-precision geometric calculation',
                    consultationOutput: 'The intersection coordinate is (42.5, 78.1).',
                    turnCount: 2,
                    turnBudget: 3,
                    sessionCount: 4,
                    sessionBudget: 10,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Consulted: gemini-2.5-pro (2/3)'), findsOneWidget);
      await tester.tap(find.byType(AdkModelConsultBadge));
      await tester.pump();
      expect(badgeTapped, isTrue);

      expect(find.text('Model Escalation: gemini-2.5-pro'), findsOneWidget);
      // Tap to expand
      await tester.tap(find.text('Model Escalation: gemini-2.5-pro'));
      await tester.pumpAndSettle();

      expect(find.text('Turn Budget: 2 / 3'), findsOneWidget);
      expect(find.text('Session: 4/10'), findsOneWidget);
      expect(
        find.text('The intersection coordinate is (42.5, 78.1).'),
        findsOneWidget,
      );
    });

    testWidgets('AdkClassifierCard renders decision and alternative probabilities',
        (WidgetTester tester) async {
      String? tappedRoute;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkClassifierCard(
              title: 'Intent Classification',
              question: 'Categorize the user inquiry into support departments.',
              selectedRoute: 'billing',
              confidence: 0.942,
              probabilities: const <String, double>{
                'billing': 0.942,
                'technical': 0.045,
                'general': 0.013,
              },
              onRouteSelected: (String r) => tappedRoute = r,
            ),
          ),
        ),
      );

      expect(find.text('Intent Classification'), findsOneWidget);
      expect(find.text('Confidence: 94.2%'), findsOneWidget);
      expect(find.text('billing'), findsNWidgets(2)); // in Chip and in breakdown
      expect(find.text('technical'), findsOneWidget);
      expect(find.text('94.2%'), findsOneWidget);
      expect(find.text('4.5%'), findsOneWidget);

      await tester.tap(find.text('technical'));
      await tester.pump();
      expect(tappedRoute, 'technical');
    });

    testWidgets('AdkWorkflowGraphView renders nodes and handles node tap',
        (WidgetTester tester) async {
      AdkGraphNode? tappedNode;

      final List<AdkGraphNode> nodes = <AdkGraphNode>[
        const AdkGraphNode(
          id: 'start',
          label: 'Start Order',
          status: AdkGraphNodeStatus.completed,
        ),
        const AdkGraphNode(
          id: 'validate',
          label: 'Validate Stock',
          status: AdkGraphNodeStatus.running,
          subtitle: 'Checking warehouse A',
        ),
        const AdkGraphNode(
          id: 'fulfill',
          label: 'Fulfill',
          status: AdkGraphNodeStatus.pending,
        ),
      ];

      final List<AdkGraphEdge> edges = <AdkGraphEdge>[
        const AdkGraphEdge(fromId: 'start', toId: 'validate', label: 'valid'),
        const AdkGraphEdge(fromId: 'validate', toId: 'fulfill', label: 'in-stock'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkWorkflowGraphView(
              nodes: nodes,
              edges: edges,
              onNodeTap: (AdkGraphNode n) => tappedNode = n,
            ),
          ),
        ),
      );

      expect(find.text('Workflow Execution Graph'), findsOneWidget);
      expect(find.text('Start Order'), findsOneWidget);
      expect(find.text('Validate Stock'), findsOneWidget);
      expect(find.text('Checking warehouse A'), findsOneWidget);
      expect(find.text('Fulfill'), findsOneWidget);
      expect(find.text('valid'), findsOneWidget);
      expect(find.text('in-stock'), findsOneWidget);

      await tester.tap(find.text('Validate Stock'));
      await tester.pump();
      expect(tappedNode?.id, 'validate');
    });

    testWidgets('Customization builders work across all widgets', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  AdkInterruptBanner(
                    toolName: 'custom_banner_tool',
                    actionBuilder: (BuildContext ctx, VoidCallback? onResume) =>
                        const Text('CustomBannerAction'),
                  ),
                  AdkInterruptCard(
                    toolName: 'custom_card_tool',
                    headerBuilder: (BuildContext ctx) => const Text('CustomHeaderWidget'),
                    actionsBuilder: (
                      BuildContext ctx,
                      void Function(String? val)? onResume,
                      VoidCallback? onCancel,
                      bool isProcessing,
                    ) =>
                        const Text('CustomActionsWidget'),
                  ),
                  AdkCascadeLiveBar(
                    isListening: true,
                    customLeading: const Text('CustomLeadingMic'),
                    customTrailing: const Text('CustomTrailingEnd'),
                    waveVisualizerBuilder: (
                      BuildContext ctx,
                      bool isActive,
                      bool isSpeaking,
                      bool isBargeIn,
                    ) =>
                        const Text('CustomWaveWidget'),
                  ),
                  AdkClassifierCard(
                    selectedRoute: 'route_a',
                    probabilities: const <String, double>{'route_a': 0.8},
                    customRouteTileBuilder: (
                      BuildContext ctx,
                      String route,
                      double prob,
                      bool isSelected,
                      VoidCallback? onTap,
                    ) =>
                        Text('CustomRouteTile: $route'),
                  ),
                  AdkWorkflowGraphView(
                    orientation: Axis.vertical,
                    nodes: const <AdkGraphNode>[
                      AdkGraphNode(id: 'n1', label: 'Node 1'),
                      AdkGraphNode(id: 'n2', label: 'Node 2'),
                    ],
                    edges: const <AdkGraphEdge>[
                      AdkGraphEdge(fromId: 'n1', toId: 'n2', label: 'step'),
                    ],
                    nodeBuilder: (
                      BuildContext ctx,
                      AdkGraphNode n,
                      bool isActive,
                      AdkGraphNodeStatus status,
                      VoidCallback? onTap,
                    ) =>
                        Text('CustomNode: ${n.id}'),
                    edgeBuilder: (BuildContext ctx, AdkGraphEdge? e, bool isLast) =>
                        Text('CustomEdge: ${e?.fromId}->${e?.toId}'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('CustomBannerAction'), findsOneWidget);
      expect(find.text('CustomHeaderWidget'), findsOneWidget);
      expect(find.text('CustomActionsWidget'), findsOneWidget);
      expect(find.text('CustomLeadingMic'), findsOneWidget);
      expect(find.text('CustomTrailingEnd'), findsOneWidget);
      expect(find.text('CustomWaveWidget'), findsOneWidget);
      expect(find.text('CustomRouteTile: route_a'), findsOneWidget);
      expect(find.text('CustomNode: n1'), findsOneWidget);
      expect(find.text('CustomNode: n2'), findsOneWidget);
      expect(find.text('CustomEdge: n1->n2'), findsOneWidget);
    });

    test('AdkFormatters formats tokens, durations, bytes, and JSON correctly', () {
      expect(AdkFormatters.formatTokens(450), '450 tokens');
      expect(AdkFormatters.formatTokens(450, compact: true), '450');
      expect(AdkFormatters.formatTokens(2500), '2.5k tokens');
      expect(AdkFormatters.formatTokens(2500, compact: true), '2.5k');
      expect(AdkFormatters.formatTokens(1250000), '1.3M tokens');
      expect(AdkFormatters.formatTokens(1250000, compact: true), '1.3M');

      expect(AdkFormatters.formatDuration(const Duration(milliseconds: 250)), '250ms');
      expect(AdkFormatters.formatDuration(const Duration(seconds: 4, milliseconds: 200)), '4.20s');
      expect(AdkFormatters.formatDuration(const Duration(minutes: 3, seconds: 15)), '3m 15s');

      expect(AdkFormatters.formatBytes(500), '500 B');
      expect(AdkFormatters.formatBytes(2048), '2.0 KB');
      expect(AdkFormatters.formatBytes(1024 * 1024 * 3), '3.0 MB');

      expect(AdkFormatters.formatJson(<String, dynamic>{'status': 'ok'}), contains('"status": "ok"'));
      expect(AdkFormatters.formatJson(null), '');
    });

    test('AdkEventStreamUtils extracts tool calls, token usage, and model consult metadata', () {
      final Event toolCallEvent = Event(
        invocationId: 'inv-1',
        author: 'model',
        timestamp: 1729000000.0,
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              name: 'lookup_user',
              args: <String, dynamic>{'userId': 'u-99'},
              id: 'call-1',
            ),
          ],
        ),
      );

      final List<AdkToolCallInfo> toolCalls = AdkEventStreamUtils.extractToolCalls(toolCallEvent);
      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.toolName, 'lookup_user');
      expect(toolCalls.first.callId, 'call-1');
      expect(toolCalls.first.arguments['userId'], 'u-99');

      final Event usageEvent = Event(
        invocationId: 'inv-2',
        author: 'model',
        usageMetadata: <String, dynamic>{
          'prompt_token_count': 120,
          'candidates_token_count': 45,
          'total_token_count': 165,
          'thought_tokens': 20,
        },
      );

      final AdkTokenUsage? usage = AdkEventStreamUtils.extractTokenUsage(usageEvent);
      expect(usage, isNotNull);
      expect(usage!.promptTokens, 120);
      expect(usage.completionTokens, 45);
      expect(usage.totalTokens, 165);
      expect(usage.thoughtTokens, 20);

      final Event consultEvent = Event(
        invocationId: 'inv-3',
        author: 'model',
        customMetadata: <String, dynamic>{
          'model_consult': true,
          'advisor_model': 'gemini-2.5-pro',
          'escalation_reason': 'High difficulty math',
          'turn_count': 2,
          'turn_budget': 5,
        },
      );

      expect(AdkEventStreamUtils.isModelConsultEvent(consultEvent), isTrue);
      final ({String? advisorModel, String? escalationReason, int? turnBudget, int? turnCount}) info =
          AdkEventStreamUtils.extractModelConsultInfo(consultEvent);
      expect(info.advisorModel, 'gemini-2.5-pro');
      expect(info.escalationReason, 'High difficulty math');
      expect(info.turnCount, 2);
      expect(info.turnBudget, 5);
    });

    testWidgets('AdkColorUtils resolves status and confidence colors correctly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              final Color highConf = AdkColorUtils.confidenceColor(context, 0.95);
              final Color midConf = AdkColorUtils.confidenceColor(context, 0.65);
              final Color lowConf = AdkColorUtils.confidenceColor(context, 0.2);

              expect(highConf, Colors.green.shade600);
              expect(midConf, Colors.orange.shade700);
              expect(lowConf, Theme.of(context).colorScheme.error);

              final Color completed =
                  AdkColorUtils.nodeStatusColor(context, AdkGraphNodeStatus.completed);
              final Color failed =
                  AdkColorUtils.nodeStatusColor(context, AdkGraphNodeStatus.failed);
              expect(completed, Colors.green.shade600);
              expect(failed, Theme.of(context).colorScheme.error);

              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });
}
