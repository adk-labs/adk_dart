import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/adk_dart.dart';

Future<void> main() async {
  final String? apiKey = Platform.environment['GEMINI_API_KEY'] ??
      Platform.environment['GOOGLE_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Please set GEMINI_API_KEY or GOOGLE_API_KEY environment variable.');
    exit(1);
  }

  // 1. Define multimodal agent
  final Agent agent = Agent(
    name: 'vision_agent',
    model: Gemini(
      model: 'gemini-2.5-flash',
      environment: <String, String>{'GEMINI_API_KEY': apiKey},
    ),
    instruction: '''
You are an expert visual analyst assistant.
Analyze the provided image and describe what you see, identifying key objects and features.
''',
  );

  final InMemoryRunner runner = InMemoryRunner(agent: agent);
  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'user_1',
    sessionId: 'session_vision',
  );

  // 1x1 transparent PNG sample bytes
  final List<int> samplePngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  // Create multimodal message with text and image
  final Content multimodalMessage = Content(
    role: 'user',
    parts: <Part>[
      Part(text: 'Please describe this sample image:'),
      Part(
        inlineData: InlineData(
          mimeType: 'image/png',
          data: samplePngBytes,
        ),
      ),
    ],
  );

  print('Sending multimodal prompt (Image + Text) to Gemini Agent...');
  await for (final Event event in runner.runAsync(
    userId: 'user_1',
    sessionId: session.id,
    newMessage: multimodalMessage,
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
