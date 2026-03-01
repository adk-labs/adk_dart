import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_adk_example/ui/core/widgets/chat_example_view.dart';
import 'package:flutter_adk_example/ui/core/widgets/example_app.dart';

void main() {
  Future<void> openExample(
    WidgetTester tester,
    String title, {
    required String summarySnippet,
  }) async {
    final Finder tile = find.widgetWithText(ListTile, title);
    await tester.dragUntilVisible(
      tile,
      find.byType(ListView).last,
      const Offset(0, -220),
    );
    await tester.tap(tile, warnIfMissed: false);
    await tester.pumpAndSettle();
    if (find.byType(ChatExampleView).evaluate().isEmpty) {
      await tester.tap(find.text(title).last, warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    expect(find.byType(ChatExampleView), findsOneWidget);
    expect(find.text(title), findsAtLeastNWidgets(1));
    expect(find.textContaining(summarySnippet), findsAtLeastNWidgets(1));
  }

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
    expect(find.byType(ChatExampleView), findsOneWidget);
    expect(
      find.textContaining('Single Agent + FunctionTool'),
      findsAtLeastNWidgets(1),
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    await openExample(
      tester,
      'Multi-Agent Coordinator Example',
      summarySnippet: 'Coordinator/Dispatcher pattern',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    await openExample(
      tester,
      'Workflow Agents Example',
      summarySnippet: 'Sequential + Parallel + Loop',
    );
  });
}
