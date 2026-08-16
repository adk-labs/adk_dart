import 'dart:io';

import 'package:adk_dart/adk_dart.dart';

Future<void> main() async {
  final String? apiKey = Platform.environment['GEMINI_API_KEY'] ??
      Platform.environment['GOOGLE_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Please set GEMINI_API_KEY or GOOGLE_API_KEY environment variable.');
    exit(1);
  }

  // Define an agent with GetUserChoiceTool
  final Agent agent = Agent(
    name: 'travel_planner',
    model: Gemini(
      model: 'gemini-2.5-flash',
      environment: <String, String>{'GEMINI_API_KEY': apiKey},
    ),
    instruction: '''
You are a helpful travel planner.
When the user asks for a recommendation, present 2-3 distinct destinations and use the get_user_choice tool to ask which one the user prefers.
After receiving the choice, provide a tailored 1-day itinerary for that destination.
''',
    tools: <Object>[getUserChoice],
  );

  final InMemoryRunner runner = InMemoryRunner(agent: agent);
  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'user_1',
    sessionId: 'session_hitl',
  );

  print('=== Step 1: User asks for recommendations ===');
  await for (final Event event in runner.runAsync(
    userId: 'user_1',
    sessionId: session.id,
    newMessage: Content.userText('Where should I go for a weekend trip?'),
  )) {
    final String text = event.content?.parts
            .where((Part p) => p.text != null)
            .map((Part p) => p.text!)
            .join(' ') ??
        '';
    if (text.isNotEmpty) {
      print('[${event.author}] $text');
    }
  }

  print('\n=== Step 2: User responds with their choice ===');
  await for (final Event event in runner.runAsync(
    userId: 'user_1',
    sessionId: session.id,
    newMessage: Content.userText('Option 1 sounds amazing!'),
  )) {
    final String text = event.content?.parts
            .where((Part p) => p.text != null)
            .map((Part p) => p.text!)
            .join(' ') ??
        '';
    if (text.isNotEmpty) {
      print('[${event.author}] $text');
    }
  }
}
