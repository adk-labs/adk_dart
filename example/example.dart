import 'package:adk_dart/adk_dart.dart';

/// A simple example demonstrating how to define an [LlmAgent] and run it with [InMemoryRunner].
Future<void> main() async {
  final agent = LlmAgent(
    name: 'greeter',
    model: 'gemini-2.5-flash',
    instruction: 'You are a friendly greeting assistant.',
  );

  final runner = InMemoryRunner(agent: agent);
  final session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'user_1',
    sessionId: 'session_1',
  );

  await for (final event in runner.runAsync(
    userId: 'user_1',
    sessionId: session.id,
    newMessage: Content.userText('Hello! Who are you?'),
  )) {
    if (event.content != null) {
      for (final part in event.content!.parts) {
        if (part.text != null) {
          print(part.text);
        }
      }
    }
  }

  await runner.close();
}
