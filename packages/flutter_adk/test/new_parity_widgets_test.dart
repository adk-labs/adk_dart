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
  });
}
