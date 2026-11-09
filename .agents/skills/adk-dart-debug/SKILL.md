---
name: adk-dart-debug
description: >-
  Diagnoses and fixes misbehaving ADK Dart agents and workflows using Event
  stream inspection, DebugLoggingPlugin, adk web HTTP/SSE endpoints (/run,
  /run_sse, /debug/trace), and known ADK Dart failure modes. Use when an agent
  produces wrong or empty output, calls the wrong tool, skips tools when
  outputSchema is set, throws ArgumentError/StateError on LlmAgent or Workflow
  construction, pauses unexpectedly on RequestInput or confirmation, or fails
  to see parent context across subAgents / task branches. Don't use for creating
  a new agent from scratch (use adk-dart-agent-builder).
---

# ADK Dart Debugging & Failure Modes

Checked against `adk_dart` `2026.11.8` (`adk-python` `2.14.0` baseline).

## 1. Enable Structured Debug Logging (`DebugLoggingPlugin`)

Attach `DebugLoggingPlugin` (or `LoggingPlugin`) to `Runner` / `InMemoryRunner` to inspect exact `LlmRequest` payloads, system instructions, tool declarations, and `LlmResponse` parts:

```dart
import 'package:adk_dart/adk_dart.dart';

final InMemoryRunner runner = InMemoryRunner(
  agent: rootAgent,
  plugins: <BasePlugin>[
    DebugLoggingPlugin(includeSystemInstruction: true),
  ],
);
```

---

## 2. Inspect the `Event` Stream Step-by-Step

Every turn is a sequence of `Event` objects on `runner.runAsync(...)`. Log each event before filtering by `event.isFinalResponse()` to pinpoint where execution diverges:

```dart
await for (final Event e in runner.runAsync(
  userId: 'debug_user',
  sessionId: session.id,
  newMessage: Content.userText('Test prompt'),
)) {
  print(
    '[id=${e.id}] author=${e.author} branch=${e.branch} '
    'scope=${e.isolationScope} node=${e.nodeInfo?.path} '
    'partial=${e.partial} final=${e.isFinalResponse()} '
    'calls=${e.getFunctionCalls().map((FunctionCall c) => c.name).toList()} '
    'responses=${e.getFunctionResponses().map((FunctionResponse r) => r.name).toList()} '
    'stateDelta=${e.actions.stateDelta} '
    'error=${e.errorCode ?? ""}:${e.errorMessage ?? ""}',
  );
}
```

### What Each Field Tells You
- `e.author`: Which agent or workflow node produced the event.
- `e.branch` / `e.isolationScope`: Sub-agent or task isolation scope. Events with a different `isolationScope` are hidden from sibling/child isolated runs.
- `e.nodeInfo?.path`: Hierarchical ADK 2.0 `Workflow` node execution path (e.g., `parallel_pipeline/fetch_a`).
- `e.getFunctionCalls()` / `e.getFunctionResponses()`: Tool calls requested by the model and the exact JSON payload returned by the tool.
- `e.actions.stateDelta` / `e.actions.artifactDelta`: State keys and artifacts mutated during that step.
- `e.actions.transferToAgent` / `e.actions.escalate`: Whether the agent transferred control or escalated out of a `LoopAgent`.
- `e.errorCode` / `e.errorMessage`: Model error code (e.g., `MALFORMED_FUNCTION_CALL`, `MAX_TOKENS`, `INVOCATION_ABORTED`) or runtime failure details.

---

## 3. Drive and Inspect via `adk web` HTTP Endpoints

Start the local developer server:

```bash
adk web --port 8000 .
```

Drive and inspect sessions via `curl`:

```bash
# 1. List discovered apps
curl -s http://127.0.0.1:8000/list-apps

# 2. Create a session with initial state
curl -s -X POST http://127.0.0.1:8000/apps/my_agent/users/u1/sessions \
  -H "Content-Type: application/json" \
  -d '{"state": {"env": "staging"}}'

# 3. Run a turn and return all Event objects as a JSON array
curl -s -X POST http://127.0.0.1:8000/run \
  -H "Content-Type: application/json" \
  -d '{
    "appName": "my_agent",
    "userId": "u1",
    "sessionId": "<SESSION_ID>",
    "newMessage": {"role": "user", "parts": [{"text": "Hello"}]}
  }'

# 4. Inspect full session history & current state
curl -s http://127.0.0.1:8000/apps/my_agent/users/u1/sessions/<SESSION_ID>

# 5. Fetch telemetry trace for a specific event ID
curl -s http://127.0.0.1:8000/debug/trace/<EVENT_ID>
```

---

## 4. Common ADK Dart Failure Modes & Fixes

| Symptom | Root Cause | Fix |
| --- | --- | --- |
| **`ArgumentError` when constructing `LlmAgent` (`temperature`, `topP`, `maxOutputTokens`)** | Generation parameters were passed inside `LlmAgent` config maps instead of `generateContentConfig`. | Pass `generateContentConfig: GenerateContentConfig(temperature: 0.2, maxOutputTokens: 2048)` on `LlmAgent`. |
| **`ArgumentError` on `LlmAgent` with `maxParallelWorkers`** | `maxParallelWorkers` was set without enabling `parallelWorker: true` and `mode: 'task'`. | Set `mode: 'task', parallelWorker: true, maxParallelWorkers: 4`. |
| **`ArgumentError: tokenThreshold and eventRetentionSize must be set together`** | Only one of `tokenThreshold` or `eventRetentionSize` was passed to `EventsCompactionConfig`. | Provide both `tokenThreshold` and `eventRetentionSize` together on `EventsCompactionConfig`. |
| **`StateError` when calling `await ctx.runNode(...)` inside a `Workflow` node** | Parent node did not opt into replay-on-resume for dynamic child scheduling. | Set `rerunOnResume: true` on the `FunctionNode` (or `BaseNode` subclass) that calls `ctx.runNode(...)`. |
| **Instruction throws key lookup error on `{my_var}`** | `{my_var}` is missing from `session.state` when `InstructionRequestProcessor` interpolates the instruction. | Initialize `'my_var'` in `createSession(state: ...)` or make the placeholder optional with `{my_var?}` (or disable interpolation via `InstructionProvider`). |
| **Tool fails silently and the model hallucinates or apologizes** | Tool exceptions/errors are returned to the LLM inside `FunctionResponse(response: {'error': ...})` rather than crashing the stream. | Inspect `event.getFunctionResponses()` in the event stream, register `onToolErrorCallback` on `LlmAgent`, or attach `ReflectAndRetryToolPlugin(maxRetries: 3)` to `Runner(plugins: [...])`. |
| **Agent emits raw JSON or skips tools when `outputSchema` is set** | When `outputSchema` is combined with other tools, ADK injects the synthetic `set_model_response` tool so the model can call tools first and then submit structured output. Weaker models may call `set_model_response` immediately. | Add explicit instruction guidance (`"Call the required lookup tools first, then call set_model_response with the final answer"`) or attach `ReflectAndRetryModelPlugin()`. |
| **Sub-agent or `mode: 'task'` worker cannot see parent conversation** | Task agents (`mode: 'task'`, `mode: 'single_turn'`) and `AgentTool` invocations run in an isolated `isolationScope` / `branch`. | Pass required context explicitly through the task/tool arguments or store shared values in `session.state` and reference `{key}` in the sub-agent's `instruction`. |
| **Agent run stops before producing text (`isFinalResponse() == true` with a `FunctionCall`)** | The run paused on a confirmation-gated tool (`adk_request_confirmation`), auth request (`adk_request_credential`), long-running tool (`longRunningToolIds`), or workflow `RequestInput`. | Check `event.longRunningToolIds` and `event.getFunctionCalls()`. Resume by calling `runner.runAsync(...)` with the corresponding `FunctionResponse` (or user input for `RequestInput`). |
| **`UnsupportedError` on Flutter Web / `dart2wasm`** | Imported `package:adk_dart/adk_dart.dart` or used `FunctionTool` (which relies on `dart:mirrors`) in a Web build. | Import `package:adk_dart/adk_core.dart` (or `package:flutter_adk/flutter_adk.dart`) and subclass `BaseTool` with an explicit `getDeclaration()`. |
