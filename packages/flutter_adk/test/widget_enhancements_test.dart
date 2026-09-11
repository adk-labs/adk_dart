import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockNode extends BaseNode {
  _MockNode() : super(name: 'workflow_step');

  @override
  FutureOr<Object?> run(WorkflowContext context, Object? nodeInput) async {
    return {'status': 'done'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdkHumanInTheLoopCard tests', () {
    testWidgets('renders action description, arguments, and buttons', (WidgetTester tester) async {
      bool approved = false;
      bool rejected = false;
      bool modified = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkHumanInTheLoopCard(
              toolName: 'transfer_funds',
              actionDescription: 'Transfer funds to recipient',
              arguments: const <String, dynamic>{'amount': 1000, 'to': 'user_42'},
              warningMessage: 'Non-reversible transaction',
              onApprove: () => approved = true,
              onReject: () => rejected = true,
              onModify: () => modified = true,
            ),
          ),
        ),
      );

      expect(find.text('Approval Required: transfer_funds'), findsOneWidget);
      expect(find.text('Transfer funds to recipient'), findsOneWidget);
      expect(find.text('Non-reversible transaction'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Modify'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      expect(approved, isTrue);

      await tester.tap(find.text('Reject'));
      expect(rejected, isTrue);

      await tester.tap(find.text('Modify'));
      expect(modified, isTrue);
    });

    testWidgets('renders finalized decision state', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkHumanInTheLoopCard(
              toolName: 'delete_database',
              decision: 'approved',
            ),
          ),
        ),
      );

      expect(find.text('Action Approved'), findsOneWidget);
      expect(find.text('APPROVED'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
    });
  });

  group('AdkArtifactCard and AdkArtifactViewer tests', () {
    testWidgets('renders AdkArtifactCard and displays file metadata', (WidgetTester tester) async {
      const artifact = AdkArtifactItem(
        name: 'summary_report.md',
        content: '# Analysis Report\nAll systems nominal.',
        version: '1.0',
        sizeBytes: 2048,
        mimeType: 'text/markdown',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkArtifactCard(artifact: artifact),
          ),
        ),
      );

      expect(find.text('summary_report.md'), findsOneWidget);
      expect(find.textContaining('v1.0'), findsOneWidget);
      expect(find.textContaining('2.0 KB'), findsOneWidget);
    });

    testWidgets('renders AdkArtifactViewer and copies content', (WidgetTester tester) async {
      const artifact = AdkArtifactItem(
        name: 'config.json',
        content: '{"env": "production"}',
        mimeType: 'application/json',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkArtifactViewer(artifact: artifact),
          ),
        ),
      );

      expect(find.text('config.json'), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.copy_rounded));
      await tester.pump();
      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('AdkMessageBubble Tool Integration tests', () {
    testWidgets('renders expandable AdkToolCallCard inside AdkMessageBubble for tool role', (WidgetTester tester) async {
      final toolMsg = AdkChatMessage.tool(
        id: 't1',
        toolName: 'search_database',
        toolArgs: <String, dynamic>{'query': 'finance'},
        toolResult: <String, dynamic>{'matches': 5},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkMessageBubble(
              message: toolMsg,
              useToolCallCard: true,
            ),
          ),
        ),
      );

      expect(find.text('Tool: search_database'), findsOneWidget);
      expect(find.text('Success'), findsOneWidget);

      // Tap card to expand
      await tester.tap(find.text('Tool: search_database'));
      await tester.pumpAndSettle();

      expect(find.text('Arguments:'), findsOneWidget);
      expect(find.text('Result:'), findsOneWidget);
      expect(find.textContaining('finance'), findsOneWidget);
    });
  });

  group('AdkToolInspectorView tests with NodeTool', () {
    testWidgets('displays input and output schema for NodeTool', (WidgetTester tester) async {
      final node = _MockNode();
      final nodeTool = NodeTool(
        name: 'workflow_step',
        description: 'Processes data through node',
        node: node,
        inputSchema: <String, dynamic>{'type': 'object', 'properties': {'id': {'type': 'string'}}},
        outputSchema: <String, dynamic>{'type': 'object', 'properties': {'status': {'type': 'string'}}},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkToolInspectorView(
              tools: <Object>[nodeTool],
            ),
          ),
        ),
      );

      expect(find.text('workflow_step'), findsOneWidget);
      expect(find.text('Processes data through node'), findsOneWidget);

      // Expand tile
      await tester.tap(find.text('workflow_step'));
      await tester.pumpAndSettle();

      expect(find.text('Input Schema:'), findsOneWidget);
      expect(find.text('Output Schema:'), findsOneWidget);
      expect(find.textContaining('"type": "object"'), findsWidgets);
    });
  });
}
