import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_adk_example/main.dart';

void main() {
  testWidgets('renders basic and multi-agent examples', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Flutter ADK Examples'), findsOneWidget);
    expect(find.text('Set API Key'), findsOneWidget);
    expect(find.text('Basic Chatbot'), findsOneWidget);
    expect(find.text('Multi-Agent'), findsOneWidget);

    expect(find.text('Basic Chatbot Example'), findsOneWidget);
    expect(find.textContaining('단일 Agent + Tool'), findsOneWidget);

    await tester.tap(find.text('Multi-Agent'));
    await tester.pumpAndSettle();

    expect(find.text('Multi-Agent Coordinator Example'), findsOneWidget);
    expect(find.textContaining('Coordinator/Dispatcher 패턴'), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
  });
}
