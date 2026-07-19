import 'dart:io';
import 'package:adk_dart/adk_dart.dart' as adk;
import 'package:adk_litertlm/adk_litertlm.dart';
import 'package:litertlm/litertlm.dart' as litert;

Future<void> main() async {
  // 1. Resolve local Gemma .bin model file path
  final String? modelPath = Platform.environment['LITERT_MODEL_PATH'];
  if (modelPath == null || modelPath.isEmpty) {
    print('================================================================');
    print('[Notice] LITERT_MODEL_PATH environment variable is not set.');
    print('To run this example with a real on-device model, set the path:');
    print('  export LITERT_MODEL_PATH="/path/to/gemma-2b-it-cpu-int4.bin"');
    print('================================================================\n');
    print('Exiting example. (To test on-device Gemma, download the model from Kaggle Models)');
    return;
  }

  final File file = File(modelPath);
  if (!file.existsSync()) {
    print('[Error] Model file does not exist at path: $modelPath');
    return;
  }

  print('Loading LiteRT-LM Engine with model: $modelPath ...');

  // 2. Initialize the LiteRT-LM Engine and ADK LiteRtLmModel
  final litert.EngineConfig config = litert.EngineConfig(
    modelPath: modelPath,
  );

  final LiteRtLmModel model = LiteRtLmModel.fromConfig(
    config,
    model: 'gemma-2b-it',
  );

  // 3. Define the agent
  final adk.Agent agent = adk.Agent(
    name: 'on_device_gemma_agent',
    model: model,
    instruction: 'You are a helpful local assistant. Answer in Korean and keep your replies brief.',
  );

  final adk.InMemoryRunner runner = adk.InMemoryRunner(agent: agent);
  final adk.Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'device_user',
    sessionId: 'device_session',
  );

  final String prompt = '인공지능이란 무엇인가요? 1문장으로 요약해 주세요.';
  print('User: $prompt');

  try {
    await for (final adk.Event event in runner.runAsync(
      userId: 'device_user',
      sessionId: session.id,
      newMessage: adk.Content.userText(prompt),
    )) {
      final String text =
          event.content?.parts
              .where((adk.Part part) => part.text != null)
              .map((adk.Part part) => part.text!)
              .join(' ') ??
          '';
      
      if (text.isNotEmpty) {
        print('[${event.author}] $text');
      }
    }
  } catch (e) {
    print('\n[Error] Failed to execute on-device Gemma: $e');
  } finally {
    // Release native resources held by LiteRT engine
    await model.close();
  }
}
