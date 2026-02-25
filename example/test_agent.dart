import 'dart:io';
import 'package:adk_dart/adk_dart.dart';

String getWeather(String location) {
  if (location.toLowerCase().contains('seoul')) {
    return 'Sunny, 20°C';
  }
  return 'Cloudy, 15°C';
}

Future<void> main() async {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null) {
    print(
      'Please set GEMINI_API_KEY environment variable. Using a dummy LLM for now.',
    );
  }

  // Define an agent with Gemini 2.5 Flash
  final Agent agent = Agent(
    name: 'weather_agent',
    model: 'gemini-2.5-flash',
    tools: [
      FunctionTool(
        func: getWeather,
        name: 'getWeather',
        description: 'Get the current weather for a specified location',
      ),
    ],
  );

  final InMemoryRunner runner = InMemoryRunner(agent: agent);
  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'test_user',
    sessionId: 'test_session',
  );

  print('Sending message to agent: What is the weather in Seoul?');

  try {
    await for (final Event event in runner.runAsync(
      userId: 'test_user',
      sessionId: session.id,
      newMessage: Content.userText('What is the weather in Seoul?'),
    )) {
      final String text =
          event.content?.parts
              .where((Part part) => part.text != null)
              .map((Part part) => part.text!)
              .join(' ') ??
          '';

      final String toolCalls = event
          .getFunctionCalls()
          .map((f) => '${f.name}(${f.args})')
          .join(', ');

      print(
        '[${event.author}] $text ${toolCalls.isNotEmpty ? ' (ToolCalls: $toolCalls)' : ''}',
      );
    }
  } catch (e, st) {
    print('Error occurred: $e');
    print(st);
  }
}
