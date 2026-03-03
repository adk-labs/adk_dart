import 'dart:io';

import 'package:adk/adk.dart';

Future<void> main() async {
  final String? apiKey =
      Platform.environment['GOOGLE_API_KEY'] ??
      Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print(
      'Set GOOGLE_API_KEY (or GEMINI_API_KEY) before running this example.',
    );
    return;
  }

  print('--- Single agent: search_assistant ---');
  await _runSingleAgentExample();

  print('');
  print('--- Multi-agent: coordinator + subAgents ---');
  await _runMultiAgentExample();
}

Future<void> _runSingleAgentExample() async {
  final Agent searchAssistant = Agent(
    name: 'search_assistant',
    model: 'gemini-2.5-flash',
    instruction:
        'You are a helpful assistant. Answer user questions using Google Search when needed.',
    description: 'An assistant that can search the web.',
    tools: <Object>[googleSearch],
  );

  await _runTurn(
    agent: searchAssistant,
    userId: 'single_user',
    sessionId: 'single_session',
    message:
        'What were the main Dart 3 language changes? Summarize in 3 bullets.',
  );
}

Future<void> _runMultiAgentExample() async {
  final Agent greeter = Agent(
    name: 'greeter',
    model: 'gemini-2.5-flash',
    description: 'Greets users and handles small talk.',
    instruction:
        'Handle greetings and short small-talk politely. Keep replies short.',
  );

  final Agent taskExecutor = Agent(
    name: 'task_executor',
    model: 'gemini-2.5-flash',
    description: 'Executes user tasks and uses search when needed.',
    instruction:
        'Handle execution-focused tasks. Use Google Search when fresh web facts are needed.',
    tools: <Object>[googleSearch],
  );

  final Agent coordinator = Agent(
    name: 'coordinator',
    model: 'gemini-2.5-flash',
    description: 'I coordinate greetings and tasks.',
    instruction: '''
You coordinate between sub-agents.
- If the user greets or does small-talk, transfer to "greeter".
- If the user asks to do or research something, transfer to "task_executor".
''',
    subAgents: <BaseAgent>[greeter, taskExecutor],
  );

  await _runTurn(
    agent: coordinator,
    userId: 'multi_user',
    sessionId: 'multi_session',
    message: 'Hi there!',
  );

  await _runTurn(
    agent: coordinator,
    userId: 'multi_user',
    sessionId: 'multi_session',
    message:
        'Find recent news about Flutter web performance and summarize in 2 bullets.',
  );
}

Future<void> _runTurn({
  required Agent agent,
  required String userId,
  required String sessionId,
  required String message,
}) async {
  final InMemoryRunner runner = InMemoryRunner(agent: agent);
  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: userId,
    sessionId: sessionId,
  );

  print('User: $message');

  await for (final Event event in runner.runAsync(
    userId: userId,
    sessionId: session.id,
    newMessage: Content.userText(message),
  )) {
    _printEvent(event);
  }
}

void _printEvent(Event event) {
  final String text =
      event.content?.parts
          .where((Part part) => part.text != null)
          .map((Part part) => part.text!)
          .join(' ') ??
      '';

  final String functionCalls = event
      .getFunctionCalls()
      .map((FunctionCall call) => '${call.name}(${call.args})')
      .join(', ');

  final String functionResponses = event
      .getFunctionResponses()
      .map(
        (FunctionResponse response) => '${response.name}(${response.response})',
      )
      .join(', ');

  final List<String> segments = <String>[if (text.isNotEmpty) text];
  if (functionCalls.isNotEmpty) {
    segments.add('ToolCalls: $functionCalls');
  }
  if (functionResponses.isNotEmpty) {
    segments.add('ToolResponses: $functionResponses');
  }

  if (segments.isNotEmpty) {
    print('[${event.author}] ${segments.join(' | ')}');
  }
}
