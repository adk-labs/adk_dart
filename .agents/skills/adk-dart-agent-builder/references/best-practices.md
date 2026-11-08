# Best Practices & Rules That Bite in ADK Dart

## 1. Web / WASM vs Dart VM Imports
- **Flutter Web / WASM (`flutter build web --wasm`)**: Always import `package:flutter_adk/flutter_adk.dart` or `package:adk_dart/adk_core.dart`. Never import `package:adk_dart/adk_dart.dart` or `package:adk/adk.dart` in code that compiles to Web, because those barrels export `dart:io`, `dart:ffi`, and `dart:mirrors` services (`SqliteSessionService`, `FileArtifactService`, `StdioConnectionParams`, `UnsafeLocalCodeExecutor`).
- **Tools on Web / AOT**: Prefer `BaseTool` subclasses with explicit `FunctionDeclaration` schemas (or `FunctionTool` with explicit declaration metadata) rather than relying on `dart:mirrors` closure reflection.

## 2. `outputSchema` + Tools Interaction
- When `outputSchema` is set on an `LlmAgent` that also has tools (including implicit `transfer_to_agent` when `subAgents` are present), ADK routes the final structured output through the internal `set_model_response` tool so the model can both call tools and return schema-validated JSON.
- If a sub-agent only produces structured output and never transfers, set `disallowTransferToParent: true` and `disallowTransferToPeers: true`.

## 3. Misplaced `GenerateContentConfig` Arguments
- Passing `temperature`, `safetySettings`, `thinkingConfig`, or `generationConfig` as top-level map keys in `LlmAgent` extra configuration throws an `ArgumentError`. Always pass them inside `generateContentConfig: GenerateContentConfig(...)`.

## 4. Always Drain or Cancel `runner.runAsync` and Close the Runner
- `runner.runAsync(...)` is a cold `Stream<Event>`. Use `await for (final Event event in runner.runAsync(...))` so the invocation completes.
- Always call `await runner.close()` when shutting down to dispose active MCP sessions and plugin queues.

## 5. Unit Testing Agents Deterministically with a Fake `BaseLlm`
Never require live API keys for unit tests. Subclass `BaseLlm` to return deterministic `LlmResponse` streams:

```dart
import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class FakeLlm extends BaseLlm {
  FakeLlm(this.responses) : super(model: 'fake-model');

  final List<LlmResponse> responses;
  final List<LlmRequest> recordedRequests = <LlmRequest>[];
  int _index = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    recordedRequests.add(request);
    yield responses[_index++ % responses.length];
  }
}

void main() {
  test('agent responds using FakeLlm', () async {
    final FakeLlm fakeModel = FakeLlm(<LlmResponse>[
      LlmResponse(content: Content.modelText('Hello from test!')),
    ]);
    final Agent agent = Agent(
      name: 'test_agent',
      model: fakeModel,
      instruction: 'Be concise.',
    );
    final InMemoryRunner runner = InMemoryRunner(agent: agent);
    final Session session = await runner.sessionService.createSession(
      appName: runner.appName,
      userId: 'u1',
      sessionId: 's1',
    );

    final List<Event> events = await runner
        .runAsync(
          userId: 'u1',
          sessionId: session.id,
          newMessage: Content.userText('Hi'),
        )
        .toList();

    expect(events.last.content?.parts.first.text, 'Hello from test!');
    expect(fakeModel.recordedRequests, hasLength(1));
    await runner.close();
  });
}
```
