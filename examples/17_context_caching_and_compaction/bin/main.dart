import 'dart:io';

import 'package:adk_dart/adk_dart.dart';

Future<void> main() async {
  final String? apiKey = Platform.environment['GEMINI_API_KEY'] ??
      Platform.environment['GOOGLE_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Please set GEMINI_API_KEY or GOOGLE_API_KEY environment variable.');
    exit(1);
  }

  // 1. Configure Gemini Context Caching
  final ContextCacheConfig cacheConfig = ContextCacheConfig(
    cacheIntervals: 5,
    ttlSeconds: 300,
    minTokens: 1000,
  );

  final Agent agent = Agent(
    name: 'document_analyzer',
    model: Gemini(
      model: 'gemini-2.5-flash',
      environment: <String, String>{'GEMINI_API_KEY': apiKey},
    ),
    instruction: '''
You are a documentation analyst.
Analyze large codebases or documents with automatic context cache reuse across conversation turns.
''',
  );

  // 2. Attach context cache configuration via App
  final App app = App(
    name: 'doc_cache_app',
    rootAgent: agent,
    contextCacheConfig: cacheConfig,
  );

  final InMemoryRunner runner = InMemoryRunner(app: app);

  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'user_1',
    sessionId: 'session_cache_opt',
  );

  print('Sending multi-turn queries with context caching enabled...');
  await for (final Event event in runner.runAsync(
    userId: 'user_1',
    sessionId: session.id,
    newMessage: Content.userText('Explain the benefits of Gemini Context Caching in ADK Dart.'),
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
