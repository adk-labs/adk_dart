import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_adk_example/ui/core/widgets/example_app.dart';

void main() {
  testWidgets('renders example list and navigates to details', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Flutter ADK Examples'), findsOneWidget);
    expect(find.text('Set API Key'), findsOneWidget);
    expect(find.text('Basic Chatbot Example'), findsOneWidget);
    expect(find.text('Single Agent + FunctionTool example.'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Basic Chatbot Example'));
    await tester.pumpAndSettle();

    expect(find.text('Basic Chatbot Example'), findsAtLeastNWidgets(1));
    expect(find.byIcon(Icons.send), findsOneWidget);
    expect(
      find.textContaining('Single Agent + FunctionTool'),
      findsAtLeastNWidgets(1),
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    final Finder transferTile = find.widgetWithText(
      ListTile,
      'Multi-Agent Coordinator Example',
    );
    await tester.ensureVisible(transferTile);
    await tester.tap(transferTile);
    await tester.pumpAndSettle();
    expect(
      find.text('Multi-Agent Coordinator Example'),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.textContaining('Coordinator/Dispatcher pattern'),
      findsAtLeastNWidgets(1),
    );
    expect(find.byIcon(Icons.send), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    final Finder workflowTile = find.widgetWithText(
      ListTile,
      'Workflow Agents Example',
    );
    await tester.ensureVisible(workflowTile);
    await tester.tap(workflowTile);
    await tester.pumpAndSettle();
    expect(find.text('Workflow Agents Example'), findsAtLeastNWidgets(1));
    expect(
      find.textContaining('Sequential + Parallel + Loop'),
      findsAtLeastNWidgets(1),
    );
    expect(find.byIcon(Icons.send), findsOneWidget);
  });
}
