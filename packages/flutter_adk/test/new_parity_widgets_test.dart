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

    testWidgets(
      'AdkSkillToolCard renders bundled resource paths on load_skill and AdkFormatters centers OAuth popups',
      (WidgetTester tester) async {
        expect(
          AdkFormatters.centeredPopupFeatures(
            screenX: 100,
            screenY: 50,
            outerWidth: 1400,
            outerHeight: 900,
          ),
          'width=600,height=700,left=500,top=150',
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AdkSkillToolCard(
                toolName: 'load_skill',
                toolArgs: <String, dynamic>{'skill_name': 'deploy'},
                toolResult: <String, dynamic>{
                  'skill_name': 'deploy',
                  'instructions': 'Run deploy script.',
                  'resources': <String>[
                    'references/guide.md',
                    'scripts/deploy.sh',
                  ],
                },
                initiallyExpanded: true,
              ),
            ),
          ),
        );

        expect(find.text('Bundled resources (2):'), findsOneWidget);
        expect(find.text('references/guide.md'), findsOneWidget);
        expect(find.text('scripts/deploy.sh'), findsOneWidget);
      },
    );

    testWidgets(
      'AdkMultiRunEvalCard renders persisted MultiRunCaseSummary, Runs strip, Pass Rate, crashed/notEvaluated badges, and per-metric run scores',
      (WidgetTester tester) async {
        final EvalSetResult evalSetResult = EvalSetResult(
          evalSetResultId: 'app_set_1',
          evalSetId: 'set_1',
          evalCaseResults: <EvalCaseResult>[
            EvalCaseResult(
              evalSetId: 'set_1',
              evalId: 'flaky_case',
              finalEvalStatus: EvalStatus.passed,
              metrics: <EvalMetricResult>[
                EvalMetricResult(
                  metric: EvalMetric.finalResponseExactMatch,
                  metricNameOverride: 'response_match_score',
                  score: 1.0,
                  threshold: 0.8,
                  evalStatus: EvalStatus.passed,
                ),
              ],
              sessionId: 's0',
              repetitionIndex: 0,
            ),
            EvalCaseResult(
              evalSetId: 'set_1',
              evalId: 'flaky_case',
              finalEvalStatus: EvalStatus.failed,
              metrics: <EvalMetricResult>[
                EvalMetricResult(
                  metric: EvalMetric.finalResponseExactMatch,
                  metricNameOverride: 'response_match_score',
                  score: 0.6,
                  threshold: 0.8,
                  evalStatus: EvalStatus.failed,
                ),
              ],
              sessionId: 's1',
              repetitionIndex: 1,
            ),
            EvalCaseResult(
              evalSetId: 'set_1',
              evalId: 'flaky_case',
              finalEvalStatus: EvalStatus.failed,
              metrics: const <EvalMetricResult>[],
              overallEvalMetricResults: const <EvalMetricResultSpec>[],
              sessionId: 's2',
              repetitionIndex: 2,
            ),
          ],
          multiRunCaseSummaries: <MultiRunCaseSummary>[
            MultiRunCaseSummary(
              evalSetId: 'set_1',
              evalId: 'flaky_case',
              finalEvalStatus: EvalStatus.passed,
              numRuns: 3,
              passedRuns: 1,
              failedRuns: 1,
              crashedRuns: 1,
              notEvaluatedRuns: 0,
              passRate: 0.5,
              metrics: <EvalMetricResult>[
                EvalMetricResult(
                  metric: EvalMetric.finalResponseExactMatch,
                  metricNameOverride: 'response_match_score',
                  score: 0.8,
                  threshold: 0.8,
                  evalStatus: EvalStatus.passed,
                ),
              ],
              metricMethods: const <String, MethodResult>{
                'response_match_score': MethodResult(
                  name: 'mean_over_invocations',
                  value: 0.8,
                  threshold: 0.8,
                  status: EvalStatus.passed,
                ),
              },
              crossRunResults: const <MethodResult>[
                MethodResult(
                  name: 'pass_at_2',
                  value: 1.0,
                  threshold: 0.9,
                  status: EvalStatus.passed,
                ),
              ],
              maxCrashedRuns: 1,
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AdkMultiRunEvalCard.fromEvalSetResult(
                  evalSetResult: evalSetResult,
                ),
              ),
            ),
          ),
        );

        expect(find.text('flaky_case'), findsOneWidget);
        expect(find.text('1/3 runs passed'), findsOneWidget);
        expect(find.text('Runs: PFC'), findsOneWidget);
        expect(find.text('Pass Rate: 50%'), findsOneWidget);
        expect(find.text('1 crashed'), findsOneWidget);
        expect(find.text('pass_at_2=1.00 (PASSED)'), findsOneWidget);
        expect(
          find.text(
            'response_match_score (mean_over_invocations): 0.80 (runs: [1.00, 0.60, -])',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Google Maps tool recognition surfaces icons and badges on AdkToolCallCard and AdkToolInspectorView',
      (WidgetTester tester) async {
        expect(AdkToolCallCard.isGoogleMapsTool('get_street_view_image'), isTrue);
        expect(AdkToolCallCard.isGoogleMapsTool('validate_address'), isTrue);
        expect(AdkToolCallCard.isGoogleMapsTool('reverse_geocode'), isTrue);
        expect(AdkToolCallCard.isGoogleMapsTool('maps:validate_address'), isTrue);
        expect(AdkToolCallCard.isGoogleMapsTool('lookup_user'), isFalse);

        expect(
          AdkToolCallCard.iconForTool('get_street_view_image'),
          Icons.streetview,
        );
        expect(
          AdkToolCallCard.iconForTool('validate_address'),
          Icons.where_to_vote_outlined,
        );
        expect(
          AdkToolCallCard.iconForTool('reverse_geocode'),
          Icons.place_outlined,
        );
        expect(
          AdkFormatters.googleMapsToolLabel('get_street_view_image'),
          'Street View Image',
        );

        const AdkToolCallInfo mapsInfo = AdkToolCallInfo(
          toolName: 'reverse_geocode',
        );
        expect(mapsInfo.isGoogleMapsTool, isTrue);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  AdkToolCallCard(
                    toolName: 'get_street_view_image',
                    toolArgs: <String, dynamic>{'location': 'Mountain View, CA'},
                  ),
                  AdkToolCallCard(
                    toolName: 'validate_address',
                    toolArgs: <String, dynamic>{'address': '1600 Amphitheatre Pkwy'},
                  ),
                  AdkToolCallCard(
                    toolName: 'reverse_geocode',
                    toolArgs: <String, dynamic>{'lat': 37.422, 'lng': -122.084},
                  ),
                ],
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.streetview), findsOneWidget);
        expect(find.byIcon(Icons.where_to_vote_outlined), findsOneWidget);
        expect(find.byIcon(Icons.place_outlined), findsOneWidget);
        expect(find.text('Google Maps'), findsNWidgets(3));
      },
    );
  });
}
