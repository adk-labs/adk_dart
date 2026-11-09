# Getting Started with ADK Dart Agents

## 1. Minimal Agent & `InMemoryRunner`

```dart
import 'package:adk_dart/adk_dart.dart';

Future<void> main() async {
  final Agent agent = Agent(
    name: 'helpful_assistant',
    model: 'gemini-2.5-flash',
    description: 'Answers general questions concisely.',
    instruction: 'You are a helpful assistant. Greet {user_name?} politely.',
  );

  final InMemoryRunner runner = InMemoryRunner(agent: agent);

  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'user_1',
    sessionId: 'session_1',
    state: <String, Object?>{'user_name': 'Alice'},
  );

  await for (final Event event in runner.runAsync(
    userId: 'user_1',
    sessionId: session.id,
    newMessage: Content.userText('What is 6 times 7?'),
  )) {
    if (event.isFinalResponse()) {
      final String text = event.content?.parts
              .where((Part p) => p.text != null && !p.thought)
              .map((Part p) => p.text!)
              .join() ??
          '';
      print('[${event.author}] $text');
    }
  }

  await runner.close();
}
```

### Key Rules
- **Instruction Placeholders**: `{key}` is replaced with `session.state['key']` (throws if missing). `{key?}` is optional and resolves to `''` when missing.
- **`generateContentConfig` Guard**: Pass model parameters (`temperature`, `topP`, `maxOutputTokens`, `safetySettings`, `thinkingConfig`) inside `generateContentConfig: GenerateContentConfig(...)` on `LlmAgent`.
- **Cold Stream**: `runner.runAsync(...)` returns a `Stream<Event>` that starts executing when listened to.

---

## 2. Reading `Event` Objects & Streaming

```dart
await for (final Event event in runner.runAsync(
  userId: 'user_1',
  sessionId: session.id,
  newMessage: Content.userText('Explain quantum computing.'),
  runConfig: RunConfig(streamingMode: StreamingMode.sse),
)) {
  if (event.partial == true) {
    // Real-time streaming delta chunk (not persisted in session history)
    final String chunk = event.content?.parts
            .where((Part p) => p.text != null && !p.thought)
            .map((Part p) => p.text!)
            .join() ??
        '';
    stdout.write(chunk);
  } else if (event.isFinalResponse()) {
    print('\n--- Final Turn Complete (author: ${event.author}) ---');
  }
}
```

Useful `Event` properties:
- `event.author`: Agent name or `'user'`.
- `event.partial`: `true` for streaming chunks; `false`/`null` for persisted events.
- `event.isFinalResponse()`: `true` when the turn's final response is emitted (or when paused on a long-running / confirmation-gated tool).
- `event.getFunctionCalls()` / `event.getFunctionResponses()`: Extracts tool calls and responses.
- `event.actions.stateDelta` / `event.actions.artifactDelta`: State and artifact mutations recorded by the event.
- `event.customMetadata`: Includes `adk:tool_display_names` and provider/A2A metadata.

---

## 3. Multi-Provider Models (`Gemini`, `AnthropicLlm`, `LiteLlm`, `GemmaLlm`, `ApigeeLlm`, `LiteRtLmModel`)

```dart
// 1. Gemini (by model name string or explicit Gemini instance)
final Agent geminiAgent = Agent(
  name: 'gemini_agent',
  model: Gemini(model: 'gemini-2.5-pro'),
);

// 2. Anthropic Claude
final Agent claudeAgent = Agent(
  name: 'claude_agent',
  model: AnthropicLlm(model: 'claude-3-7-sonnet-latest'),
);

// 3. OpenAI / Ollama / LM Studio / Groq / DeepSeek via LiteLlm
final Agent ollamaAgent = Agent(
  name: 'local_agent',
  model: LiteLlm(
    model: 'ollama_chat/gemma2:2b',
    baseUrl: 'http://localhost:11434/v1',
  ),
);

// 4. Gemma via Gemini API / Vertex AI (`GemmaLlm`) or Apigee proxy (`ApigeeLlm`)
final Agent gemmaAgent = Agent(
  name: 'gemma_agent',
  model: GemmaLlm(model: 'gemma-3-27b-it'),
);

final Agent apigeeAgent = Agent(
  name: 'apigee_agent',
  model: ApigeeLlm(model: 'apigee/gemini-2.5-flash'),
);

// 5. On-device LiteRT-LM (`package:adk_litertlm/adk_litertlm.dart`)
// import 'package:adk_litertlm/adk_litertlm.dart';
// import 'package:litertlm/litertlm.dart';
// final LiteRtLmModel onDeviceModel = LiteRtLmModel.fromConfig(
//   EngineConfig(modelPath: '/path/to/model.litertlm'),
//   model: 'gemma-3-1b',
// );
```
