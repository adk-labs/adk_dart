import 'package:adk_dart/adk_core.dart';

class _SmokeModel extends BaseLlm {
  _SmokeModel() : super(model: 'smoke-model');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('ok'));
  }
}

void main() {
  final Session session = Session(id: 's', appName: 'app', userId: 'u');
  final InMemorySessionService sessions = InMemorySessionService();
  final InMemoryTelemetryService telemetry = InMemoryTelemetryService();
  final Event event = Event(
    invocationId: 'inv',
    author: 'user',
    content: Content.userText('hello'),
  );
  final Agent agent = Agent(
    name: 'smoke_agent',
    model: _SmokeModel(),
    instruction: 'Reply with ok.',
    tools: <Object>[
      FunctionTool(
        name: 'echo',
        description: 'Echo input.',
        func: ({required String text}) => <String, Object?>{'text': text},
      ),
    ],
  );
  final InMemoryRunner runner = InMemoryRunner(agent: agent);
  final Gemini gemini = Gemini(
    model: 'gemini-2.5-flash',
    environment: <String, String>{'GEMINI_API_KEY': 'test-key'},
  );

  // Keep references to avoid tree-shake-only false positives in smoke compile.
  print(
    '${session.id}:'
    '${sessions.runtimeType}:'
    '${telemetry.runtimeType}:'
    '${event.id}:'
    '${agent.runtimeType}:'
    '${runner.runtimeType}:'
    '${gemini.runtimeType}',
  );
}
