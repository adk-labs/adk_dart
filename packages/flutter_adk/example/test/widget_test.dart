import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_adk_example/main.dart';

void main() {
  testWidgets('renders all example tabs and switches screens', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Flutter ADK Examples'), findsOneWidget);
    expect(find.text('Set API Key'), findsOneWidget);
    expect(find.text('Basic Chatbot'), findsOneWidget);
    expect(find.text('Transfer Multi-Agent'), findsOneWidget);
    expect(find.text('Workflow Combo'), findsOneWidget);
    expect(find.text('Sequential'), findsOneWidget);
    expect(find.text('Parallel'), findsOneWidget);
    expect(find.text('Loop'), findsOneWidget);
    expect(find.text('Agent Team'), findsOneWidget);
    expect(find.text('MCP Toolset'), findsOneWidget);
    expect(find.text('Skills'), findsOneWidget);

    expect(find.text('Basic Chatbot Example'), findsOneWidget);
    expect(find.textContaining('Single Agent + FunctionTool'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Transfer Multi-Agent'));
    await tester.pumpAndSettle();

    expect(find.text('Multi-Agent Coordinator Example'), findsOneWidget);
    expect(
      find.textContaining('Coordinator/Dispatcher pattern'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Workflow Combo'));
    await tester.pumpAndSettle();

    expect(find.text('Workflow Agents Example'), findsOneWidget);
    expect(find.textContaining('Sequential + Parallel + Loop'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Sequential'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sequential'));
    await tester.pumpAndSettle();
    expect(find.text('SequentialAgent Example'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Parallel'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Parallel'));
    await tester.pumpAndSettle();
    expect(find.text('ParallelAgent Example'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Loop'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Loop'));
    await tester.pumpAndSettle();
    expect(find.text('LoopAgent Example'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Agent Team'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Agent Team'));
    await tester.pumpAndSettle();
    expect(find.text('Agent Team Example'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'MCP Toolset'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'MCP Toolset'));
    await tester.pumpAndSettle();
    expect(find.text('MCP Toolset Example'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Skills'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Skills'));
    await tester.pumpAndSettle();
    expect(find.text('SkillToolset Example'), findsOneWidget);

    expect(find.byIcon(Icons.send), findsOneWidget);
  });
}
