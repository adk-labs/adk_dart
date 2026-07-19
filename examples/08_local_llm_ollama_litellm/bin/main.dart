import 'dart:io';
import 'package:adk_dart/adk_dart.dart';

Future<void> main() async {
  // 1. Configure local model details.
  // By default, local Ollama running on default port: http://localhost:11434/v1
  // Local LiteLLM proxy running on default port: http://localhost:4000/v1
  final String baseUrl = Platform.environment['LOCAL_LLM_BASE_URL'] ?? 'http://localhost:11434/v1';
  final String modelName = Platform.environment['LOCAL_LLM_MODEL'] ?? 'ollama_chat/gemma2:2b';

  print('Initializing LiteLlm to connect to local model...');
  print('Base URL: $baseUrl');
  print('Model: $modelName\n');

  // 2. Initialize the LiteLlm model adapter.
  // It will automatically use the standard HTTP invoker calling "$baseUrl/chat/completions"
  final LiteLlm model = LiteLlm(
    model: modelName,
    baseUrl: baseUrl,
  );

  // 3. Define the agent
  final Agent agent = Agent(
    name: 'local_gemma_agent',
    model: model,
    instruction: 'You are a helpful local assistant. Answer in Korean and keep your replies brief.',
  );

  final InMemoryRunner runner = InMemoryRunner(agent: agent);
  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'local_user',
    sessionId: 'local_session',
  );

  final String prompt = '인공지능이란 무엇인가요? 1문장으로 요약해 주세요.';
  print('User: $prompt');

  try {
    await for (final Event event in runner.runAsync(
      userId: 'local_user',
      sessionId: session.id,
      newMessage: Content.userText(prompt),
    )) {
      final String text =
          event.content?.parts
              .where((Part part) => part.text != null)
              .map((Part part) => part.text!)
              .join(' ') ??
          '';
      
      if (text.isNotEmpty) {
        print('[${event.author}] $text');
      }
    }
  } on HttpException catch (e) {
    print('\n[Error] Failed to connect to local LLM: $e');
    print('Ensure Ollama or LiteLLM is running locally and the model is pulled.');
  } catch (e) {
    print('\n[Error] $e');
  }
}
