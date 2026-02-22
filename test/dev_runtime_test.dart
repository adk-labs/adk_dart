import 'package:adk_dart/src/dev/project.dart';
import 'package:adk_dart/src/dev/runtime.dart';
import 'package:test/test.dart';

void main() {
  group('DevAgentRuntime', () {
    test('returns time response through tool calling loop', () async {
      final DevAgentRuntime runtime = DevAgentRuntime(
        config: const DevProjectConfig(
          appName: 'test_app',
          agentName: 'root_agent',
          description: 'test',
        ),
      );

      final session = await runtime.createSession(userId: 'u1');
      final events = await runtime.sendMessage(
        userId: 'u1',
        sessionId: session.id,
        message: 'What time is it in Seoul?',
      );

      final bool hasToolCall = events.any(
        (event) => event.getFunctionCalls().any(
          (call) => call.name == getCurrentTimeToolName,
        ),
      );
      final bool hasFinalText = events.any(
        (event) =>
            event.author == 'root_agent' &&
            (event.content?.parts.any(
                  (part) => part.text?.contains('Seoul') ?? false,
                ) ??
                false),
      );

      expect(hasToolCall, isTrue);
      expect(hasFinalText, isTrue);

      await runtime.runner.close();
    });
  });
}
