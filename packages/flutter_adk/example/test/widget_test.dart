import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:flutter_adk_example/main.dart';

void main() {
  testWidgets('renders chatbot shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Flutter ADK Chatbot'), findsOneWidget);
    expect(find.text('Set API Key'), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
  });
}
