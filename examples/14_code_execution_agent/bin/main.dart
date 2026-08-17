import 'dart:io';

import 'package:adk_dart/adk_dart.dart';

Future<void> main() async {
  final String? apiKey = Platform.environment['GEMINI_API_KEY'] ??
      Platform.environment['GOOGLE_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Please set GEMINI_API_KEY or GOOGLE_API_KEY environment variable.');
    exit(1);
  }

  // 1. Create a code-executing agent with BuiltInCodeExecutor
  final Agent agent = Agent(
    name: 'math_coder_agent',
    model: Gemini(
      model: 'gemini-3.7-flash',
      environment: <String, String>{'GEMINI_API_KEY': apiKey},
    ),
    instruction: '''
You are a mathematical problem-solving assistant.
When asked to perform complex calculations, data analysis, or numerical algorithms, write and execute code to obtain precise answers.
''',
    codeExecutor: BuiltInCodeExecutor(),
  );

  final InMemoryRunner runner = InMemoryRunner(agent: agent);
  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'user_1',
    sessionId: 'session_code_exec',
  );

  print('Asking agent to compute 50th Fibonacci number via code execution...');
  await for (final Event event in runner.runAsync(
    userId: 'user_1',
    sessionId: session.id,
    newMessage: Content.userText(
      'Calculate the 50th Fibonacci number using code execution.',
    ),
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
