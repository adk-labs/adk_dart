import 'dart:convert';

import 'package:adk_dart/adk_dart.dart';

class StubEchoModel extends BaseLlm {
  StubEchoModel() : super(model: 'stub_echo');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String prompt = request.contents.isEmpty
        ? ''
        : request.contents.last.parts
            .where((Part p) => p.text != null)
            .map((Part p) => p.text!)
            .join(' ');
    yield LlmResponse(content: Content.modelText('A2A Response: $prompt'));
  }
}

Future<void> main() async {
  // 1. Define an underlying ADK Agent
  final Agent agent = Agent(
    name: 'translator_agent',
    model: StubEchoModel(),
    description: 'Translates text between languages via A2A protocol.',
    instruction: 'Translate messages into requested language.',
  );

  // 2. Wrap agent into an A2A Application using `toA2a`
  final A2aApplication a2aApp = await toA2a(
    agent,
    host: 'localhost',
    port: 8000,
    protocol: 'http',
  );

  print('=== A2A Agent Card Auto-Generated ===');
  print(const JsonEncoder.withIndent('  ').convert(a2aApp.agentCard.toJson()));

  // 3. Execute an incoming A2A Request
  final A2aAgentExecutor executor = a2aApp.executor as A2aAgentExecutor;
  final InMemoryA2aEventQueue eventQueue = InMemoryA2aEventQueue();

  final A2aRequestContext requestContext = A2aRequestContext(
    taskId: 'task_1001',
    contextId: 'ctx_001',
    message: A2aMessage(
      messageId: 'msg_001',
      role: A2aRole.user,
      parts: <A2aPart>[
        A2aPart.text('Hello from client agent over A2A!'),
      ],
    ),
  );

  print('\n=== Executing A2A Task over EventQueue ===');
  eventQueue.stream.listen((A2aEvent event) {
    if (event is A2aTaskStatusUpdateEvent) {
      print('[A2A Task Update] status=${event.status.state}');
    }
  });

  await executor.execute(requestContext, eventQueue);

  print('\nA2A Task execution finished successfully!');
}
