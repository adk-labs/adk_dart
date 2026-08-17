import 'dart:async';
import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Deep Widget Interaction Tests', () {
    testWidgets('AdkConfirmationBanner handles approve and reject', (WidgetTester tester) async {
      bool? approved;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  approved = await AdkConfirmationBanner.showAsDialog(
                    context,
                    title: 'Tool Execution Approval',
                    toolName: 'delete_database',
                    description: 'Are you sure you want to delete the production database?',
                    confirmLabel: 'Approve',
                    denyLabel: 'Reject',
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

      expect(find.text('Tool Execution Approval'), findsOneWidget);
      expect(find.textContaining('delete_database'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(approved, isTrue);
    });

    testWidgets('AdkSessionDrawer handles session actions and empty state', (WidgetTester tester) async {
      String? selectedId;
      String? deletedId;
      bool createdNew = false;

      final sessions = <AdkSessionInfo>[
        const AdkSessionInfo(
          id: 'sess_1',
          title: 'Session One',
          messageCount: 3,
        ),
        const AdkSessionInfo(
          id: 'sess_2',
          title: 'Session Two',
          messageCount: 7,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            drawer: AdkSessionDrawer(
              sessions: sessions,
              activeSessionId: 'sess_1',
              onSessionSelected: (s) => selectedId = s.id,
              onNewSession: () => createdNew = true,
              onDeleteSession: (s) => deletedId = s.id,
            ),
            body: const Center(child: Text('Main Screen')),
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Session One'), findsOneWidget);
      expect(find.text('Session Two'), findsOneWidget);
      expect(find.text('New Chat'), findsWidgets);

      // Tap on second session
      await tester.tap(find.text('Session Two'));
      await tester.pumpAndSettle();
      expect(selectedId, equals('sess_2'));

      // Reopen drawer and delete session
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(deletedId, equals('sess_1'));

      // Tap new chat
      await tester.tap(find.text('New Chat').first);
      await tester.pumpAndSettle();
      expect(createdNew, isTrue);
    });

    testWidgets('AdkEventStreamBuilder renders stream events correctly', (WidgetTester tester) async {
      final streamController = StreamController<adk.Event>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkEventStreamBuilder(
              stream: streamController.stream,
              loadingBuilder: (context) => const Text('Loading stream...'),
              builder: (context, events) => Text('Event: ${events.firstOrNull?.author}'),
            ),
          ),
        ),
      );

      expect(find.text('Loading stream...'), findsOneWidget);

      streamController.add(adk.Event(invocationId: 'inv_1', author: 'AgentAlpha'));
      await tester.pumpAndSettle();

      expect(find.text('Event: AgentAlpha'), findsOneWidget);

      await streamController.close();
    });

    testWidgets('AdkAgentLoggerView filter categories and search query', (WidgetTester tester) async {
      final logs = <AdkAgentLogEntry>[
        AdkAgentLogEntry(
          id: 'log_1',
          timestamp: DateTime.now(),
          agentName: 'SearchAgent',
          category: AdkLogCategory.userInput,
          title: 'User Question',
          subtitle: 'How to use Flutter ADK?',
        ),
        AdkAgentLogEntry(
          id: 'log_2',
          timestamp: DateTime.now(),
          agentName: 'SearchAgent',
          category: AdkLogCategory.modelResponse,
          title: 'Model Response',
          subtitle: 'Flutter ADK provides ready-to-use widgets.',
        ),
        AdkAgentLogEntry(
          id: 'log_3',
          timestamp: DateTime.now(),
          agentName: 'SearchAgent',
          category: AdkLogCategory.toolCall,
          title: 'Tool Call: search_docs',
          subtitle: 'Executed search_docs',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentLoggerView(logs: logs),
          ),
        ),
      );

      expect(find.text('User Question'), findsOneWidget);
      expect(find.text('Model Response'), findsOneWidget);
      expect(find.text('Tool Call: search_docs'), findsOneWidget);

      // Filter by Tools only
      await tester.tap(find.text('Tool Calls'));
      await tester.pumpAndSettle();

      expect(find.text('Tool Call: search_docs'), findsOneWidget);
      expect(find.text('User Question'), findsNothing);

      // Switch back to All
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      // Search filter
      await tester.enterText(find.byType(TextField), 'Flutter');
      await tester.pumpAndSettle();

      expect(find.text('User Question'), findsOneWidget);
      expect(find.text('Model Response'), findsOneWidget);
      expect(find.text('Tool Call: search_docs'), findsNothing);
    });

    testWidgets('AdkVoiceMicButton and AdkAudioWaveVisualizer tap and render', (WidgetTester tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                AdkVoiceMicButton(
                  isListening: true,
                  onPressed: () => tapped = true,
                ),
                const AdkAudioWaveVisualizer(
                  isActive: true,
                  height: 32.0,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(AdkVoiceMicButton), findsOneWidget);
      expect(find.byType(AdkAudioWaveVisualizer), findsOneWidget);

      await tester.tap(find.byType(AdkVoiceMicButton));
      expect(tapped, isTrue);
    });
  });
}
