# adk_dart

`adk_dart` is a Dart-first port of the Agent Development Kit (ADK), using
`ref/adk-python` as the primary reference implementation.

## Current Scope (v0.1.0)

Implemented core runtime layers:

- Agent runtime: `BaseAgent`, `LlmAgent` (`Agent` alias), `Context`, `InvocationContext`
- Runner runtime: `Runner`, `InMemoryRunner`
- Session runtime: `BaseSessionService`, `InMemorySessionService`, session state prefixes (`app:`, `user:`, `temp:`)
- Event model: `Event`, `EventActions`, final-response detection
- LLM model abstraction: `BaseLlm`, `LlmRequest`, `LlmResponse`, `LLMRegistry`
- Tool runtime: `BaseTool`, `FunctionTool`, `BaseToolset`, tool-callback execution path
- LLM flow: `BaseLlmFlow`, `SingleFlow`, `AutoFlow`, function-call orchestration

This is a functional core port, not full parity yet.

## Quick Start

```dart
import 'package:adk_dart/adk_dart.dart';

class EchoModel extends BaseLlm {
  EchoModel() : super(model: 'echo');

  @override
  Stream<LlmResponse> generateContent(LlmRequest request, {bool stream = false}) async* {
    yield LlmResponse(content: Content.modelText('echo response'));
  }
}

Future<void> main() async {
  final agent = Agent(name: 'root_agent', model: EchoModel());
  final runner = InMemoryRunner(agent: agent);

  final session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'user_1',
    sessionId: 'session_1',
  );

  await for (final event in runner.runAsync(
    userId: 'user_1',
    sessionId: session.id,
    newMessage: Content.userText('hello'),
  )) {
    print(event.content?.parts.first.text);
  }
}
```

## CLI

`adk_dart` exposes an `adk` executable with `create`, `run`, and `web`.

```bash
dart pub get
dart pub global activate --source path .
adk create my_agent
adk run my_agent
adk web --port 8000 my_agent
```

`adk web --port 8000` starts a development chat UI at `http://127.0.0.1:8000`.

Caution: ADK Web for development only

ADK Web in this repository is intended for development and debugging, not
production deployments.

## Python Parity Tracking

Current progress against `ref/adk-python` is tracked in
`python_parity_status.md`.

## Test

```bash
dart test
dart analyze
```

## Porting Roadmap

Planned next parity layers from `adk-python`:

- Plugins and callback parity hardening
- Live/Bidi execution path (`run_live` semantics)
- App-level compaction/resumability edge cases
- Additional built-in tools / model integrations
- A2A, evaluation, telemetry, memory, artifact backends
