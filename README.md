# Agent Development Kit (ADK) for Dart

English | [한국어](README.ko.md) | [日本語](README.ja.md) | [中文](README.zh.md)

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![pub package](https://img.shields.io/pub/v/adk_dart.svg)](https://pub.dev/packages/adk_dart)
[![Package Sync](https://github.com/adk-labs/adk_dart/actions/workflows/package-sync.yml/badge.svg)](https://github.com/adk-labs/adk_dart/actions/workflows/package-sync.yml)

ADK Dart is an open-source, code-first Dart framework for building and running
AI agents with modular runtime primitives, tool orchestration, and MCP
integration.

It is a Dart port of ADK concepts with a focus on practical runtime compatibility and
developer ergonomics.

---

## What's New

- **MCP Protocol Core Package**: Added `packages/adk_mcp` and moved MCP
  streamable HTTP protocol handling into a dedicated package.
- **MCP Spec Hardening**: Improved MCP lifecycle and transport behavior
  (session recovery, SSE response matching by request id, cancellation
  notifications, capability-aware RPC usage).
- **Compatibility Expansion**: Added broader runtime compatibility coverage across sessions,
  toolsets, and model/tool integration layers in the `0.1.x` line.

## Key Features

- **Code-First Agent Runtime**: Build agents with `BaseAgent`, `LlmAgent`
  (`Agent` alias), and explicit invocation/session context objects.
- **Event-Driven Execution**: Run agents asynchronously with `Runner` /
  `InMemoryRunner` and stream `Event` outputs.
- **Multi-Agent Composition**: Compose agent hierarchies with `subAgents` and
  orchestrate specialized workflows.
- **Tooling Ecosystem**: Use function tools, OpenAPI tools, Google API toolsets,
  data tools (BigQuery/Bigtable/Spanner), and MCP toolsets.
- **MCP Integration**: Connect to remote MCP servers through streamable HTTP
  using `McpToolset` and `McpSessionManager` (backed by `adk_mcp`).
- **Developer CLI + Web UI**: Scaffold projects and run chat/dev server with
  the `adk` CLI (`create`, `run`, `web`, `api_server`).

## ADK Python Compatibility Status

ADK Dart is intended to behave like `adk-python` while using Dart-native
types, async streams, package structure, and platform constraints. The current
release baseline tracks `adk-python` `2.2.0`.

Status legend:

- `✅` Implemented and covered by compatibility/runtime tests.
- `⚠️` Implemented with platform, credential, or environment constraints.
- `🚧` Not fully implemented yet / planned.

| `adk-python` area | Dart status | Dart implementation surface | Notes |
| --- | --- | --- | --- |
| Package/version baseline | ✅ | `adkVersion`, package versions | `adk_dart`, `adk`, `adk_mcp`, and `flutter_adk` are aligned on `2026.6.6`; exported ADK baseline is `2.2.0`. |
| Agents and runner | ✅ | `BaseAgent`, `LlmAgent`/`Agent`, `SequentialAgent`, `ParallelAgent`, `LoopAgent`, `Runner`, `InMemoryRunner` | Core invocation, live fallback, rewind, session state, callback, and transfer behavior are ported. |
| LLM flow processors | ✅ | request/response processors under `flows/llm_flows` | Covers instructions, identity, contents, compaction, context cache, code execution, output schema, tool confirmation, auth preflight, and agent transfer. |
| Workflow runtime | ✅ | `Workflow`, `BaseNode`, function/tool/LLM-agent nodes, joins, routes, dynamic nodes, replay helpers | Python v2 workflow primitives are ported, including retry, timeout, request-input/HITL, parallel workers, replay/rehydration, graph serialization, and status-aware DOT output. |
| Events and content conversion | ✅ | `Event`, `EventActions`, content/part models, node path helpers | Includes structured event actions, node-path building, function/tool response conversion, and A2A metadata preservation. |
| Sessions and state | ✅ | in-memory, SQLite, database, Vertex AI session services, migration helpers | Local and remote session APIs are implemented; network/cloud backends require their normal credentials and endpoints. |
| Memory and artifacts | ✅ | in-memory memory, Vertex AI memory/RAG, in-memory/file/GCS artifacts | GCS/Vertex paths use HTTP/auth provider wiring and remain environment-dependent for live cloud calls. |
| Tools and toolsets | ✅ | function tools, agent tools, OpenAPI tools, Google API tools, retrieval tools, environment tools, data tools | Includes built-in Gemini tool payload compatibility for Google Search, URL Context, code execution, computer use, Google Maps, Enterprise Web Search, Vertex AI Search, and Vertex RAG. |
| MCP integration | ⚠️ | `adk_mcp`, `McpToolset`, `McpSessionManager`, `StreamableHTTPConnectionParams`, `StdioConnectionParams` | Streamable HTTP works across VM/Flutter/Web when HTTP/CORS allows it. Stdio requires local process execution and is VM-only. |
| Models/providers | ✅ | Gemini REST/live, Anthropic, LiteLLM, Gemma, Apigee, Chat Completions, OpenAI labs adapter | Provider behavior is ported with injectable transports; real provider calls still require API keys, project settings, and provider availability. |
| Auth and credentials | ✅ | auth schemes, credential manager/service, OAuth2 exchanger/refresher, service-account hooks | Ported for tool auth, auth response persistence, OAuth discovery, token exchange/refresh, and session-state credential storage. |
| Evaluation and simulation | ✅ | eval managers/services, metric evaluators, LLM-as-judge, user simulators | Local/GCS eval-set managers, trajectory/final-response/rubric/safety metrics, and simulator-driven generation are implemented. |
| Plugins and telemetry | ✅ | plugin manager, debug/global/reflection/save-artifact plugins, OpenTelemetry/SQLite/cloud telemetry | SQLite trace persistence, metrics instrumentation, auto tracing, and plugin lifecycle hooks are implemented. |
| CLI, dev server, and deploy | ✅ | `adk create/run/web/api_server/deploy/eval/eval_set/conformance/migrate` | Behavior is ported for Dart CLI usage. Some command output formatting can differ from Python because the implementation is Dart-native. |
| A2A protocol | ✅ | A2A converters, executor, agent card, JSON-RPC/REST task routes, remote A2A agent | Includes streaming, task resume/cancel/resubscribe, push notification config, metadata propagation, and persistent push callback retry queue. |
| Code execution | ⚠️ | unsafe local, built-in, container/Docker, GKE, Vertex AI code executor paths | Runtime behavior is implemented, but live execution depends on local process/Docker/Kubernetes/Vertex AI availability and policy. |
| Data/cloud integrations | ⚠️ | BigQuery, Bigtable, Spanner, Pub/Sub, Secret Manager, Agent Registry, Skill Registry, Slack, Toolbox | Runtime clients and facades are implemented; live behavior depends on cloud credentials, service enablement, and environment configuration. |
| Skills | ✅ | `Skill`, `SkillToolset`, local/in-memory/GCS skill sources, skill prompt formatting | Inline and directory-backed skills are implemented. Filesystem-backed loading is not available on Flutter Web. |
| Flutter/Web-safe API | ⚠️ | `adk_core`, `flutter_adk`, Flutter example app | Web-safe runtime APIs are exposed, but VM-only APIs (`dart:io`, `dart:ffi`, `dart:mirrors`, local process execution, local filesystem servers) are intentionally excluded. |
| OpenAPI external refs | 🚧 | OpenAPI parser/toolset | Inline and local spec handling are implemented; external multi-file `$ref` resolution is still planned. |
| Spanner PostgreSQL ANN | 🚧 | Spanner vector tooling | Core Spanner/vector paths are implemented, but PostgreSQL ANN behavior is not yet supported. |
| Speech transcription bootstrap | ⚠️ | audio transcription runtime | Transcription orchestration is present; a recognizer must be supplied per instance or through the default recognizer registration hook. |
| Python sample tree coverage | 🚧 | examples, `flutter_adk/example`, docs/worklog | Runtime behavior is prioritized first. Representative Dart/Flutter examples exist, but the full Python sample tree is not mirrored one-for-one yet. |

## Which Package Should I Use?

| If you are... | Use this package | Why |
| --- | --- | --- |
| Building Dart agents on VM/CLI (server, tooling, tests, full runtime APIs) | `adk_dart` | Primary package with the full ADK Dart runtime surface. |
| Building Dart agents on VM/CLI but prefer a short import path | `adk` | Facade package that re-exports `adk_dart` (`package:adk/adk.dart`). |
| Building a Flutter app (Android/iOS/Web/Linux/macOS/Windows) | `flutter_adk` | Flutter-focused, web-safe surface via `adk_core` with single-import ergonomics. |

Quick rule:

- Choose `adk_dart` by default.
- Choose `adk` only when you want the short package name but same behavior.
- Choose `flutter_adk` for Flutter app code, especially when Web compatibility matters.

## Design Philosophy

- `adk_dart` is the Python-compatible runtime core package.
  It preserves ADK SDK concepts and prioritizes broad feature implementation on
  Dart VM execution paths.
- `adk` is an ergonomics facade.
  It does not implement a separate runtime and simply re-exports `adk_dart`
  under a shorter package name.
- `flutter_adk` is the Flutter multi-platform layer.
  It intentionally exposes a web-safe subset (`adk_core`) so one Flutter code
  path can target Android/iOS/Web/Linux/macOS/Windows with consistent behavior.

Terminology note:

- In this repository, `VM/CLI` means Dart VM processes (CLI tools, server
  processes, tests, and non-Flutter desktop Dart apps).
- For Flutter desktop UI apps, prefer `flutter_adk` as the default integration
  package.

## Package Links

- [adk_dart](https://pub.dev/packages/adk_dart): Core ADK Dart runtime package
  with the full VM/CLI-focused API surface.
- [adk](https://pub.dev/packages/adk): Short-name facade package that
  re-exports `adk_dart` for import ergonomics.
- [flutter_adk](https://pub.dev/packages/flutter_adk): Flutter-focused package
  that exposes the web-safe ADK surface for multi-platform Flutter apps.

## Platform Support Matrix (Current)

Status legend:

- `Y` Supported
- `Partial` Partially supported / environment dependent
- `N` Not supported

| Feature / Surface | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | Notes |
| --- | --- | --- | --- | --- |
| Full API surface via `package:adk_dart/adk_dart.dart` | Y | Partial | N | Full surface includes `dart:io`, `dart:ffi`, and `dart:mirrors` paths, so Web cannot use this entrypoint directly. |
| Web-safe API surface via `package:adk_dart/adk_core.dart` | Y | Y | Y | `adk_core` intentionally excludes IO/FFI/mirrors-only APIs. |
| Agent runtime (`Agent`, `Runner`, workflows) via `adk_core` | Y | Y | Y | In-memory orchestration path is cross-platform. |
| MCP over Streamable HTTP (`StreamableHTTPConnectionParams`) | Y | Y | Y | Works where HTTP is available (Web may need CORS-compatible MCP server config). |
| MCP over stdio (`StdioConnectionParams`) | Y | Partial | N | Requires local process execution via `dart:io` `Process`; unavailable on Web. |
| Skills with inline `Skill` + `SkillToolset` | Y | Y | Y | Inline skill definitions are web-safe. |
| Directory-based skill loading (`loadSkillFromDir`) | Y | Partial | N | Uses filesystem APIs; Web path throws `UnsupportedError`. |
| CLI (`adk create/run/web/api_server/deploy`) | Y | N | N | CLI is VM/terminal-only. |
| Dev web server + A2A serving endpoints | Y | N | N | Server hosting path is VM/runtime process oriented. |
| DB/file-backed services (sqlite/postgres/mysql sessions, file artifacts) | Y | Partial | N | Relies on IO/network/file primitives; Flutter runtime support depends on host/platform policies. |

## Feature Support Matrix (Current)

This matrix is rebuilt from a fresh source audit plus targeted runtime tests
(`dev_web_server`, `cli_adk_web_server`, `mcp_http`, `mcp_tooling`,
`session_persistence`) rather than legacy compatibility notes.

Status legend:

- `Y` Supported
- `Partial` Partial / integration required
- `N` Not supported yet

### Supported / Working

| Area | Feature | Status | Notes |
| --- | --- | --- | --- |
| Core runtime | Agent execution (`Runner`, `InMemoryRunner`) | Y | Event-driven run / rewind / live paths are implemented and tested. |
| Sessions | `memory://`, local sqlite, `postgresql://`, `mysql://` session persistence | Y | SQLite(local FFI) + network backends are wired through `DatabaseSessionService`; live Postgres/MySQL roundtrip tests are included (env-gated). |
| Artifacts | `memory://` and local file artifacts | Y | Artifact CRUD/version APIs are wired through web + runner flows. |
| MCP | Streamable HTTP + stdio tool/resource/prompt flows | Y | `adk_mcp` + `McpSessionManager` cover initialize/call/pagination/notifications. |
| CLI | `create`, `run`, `web`, `api_server`, `deploy` | Y | Parsed and executed through `lib/src/dev/cli.dart`; `deploy` supports dry-run and real command execution path. |
| CLI run | `--save_session`, `--resume`, `--replay`, `--message` | Y | Session snapshot import/export and replay paths are implemented. |
| Web server | `/dev-ui` static hosting and config endpoint | Y | Bundled UI serving and SPA fallback are implemented. |
| Web server | `/health`, `/version`, `/list-apps`, `/run`, `/run_sse`, `/run_live` | Y | Core dev runtime API works and is covered by web tests. |
| Web server | Python-style session/memory/artifact routes | Y | `/apps/{app}/users/{user}/sessions...` CRUD and artifact routes are implemented. |
| Web server | Debug/Eval/Trace route families | Y | Includes `/debug/trace/*`, `/apps/{app}/metrics-info`, `/apps/{app}/eval-*`, and event graph endpoints. |
| Web options | `allow_origins`, `url_prefix`, `reload`, `reload_agents`, logo, telemetry flags | Y | Options are parsed and propagated into runtime/web context. |
| A2A | Agent card endpoints (`/.well-known/agent.json`, `/a2a/<app>/.well-known/agent.json`) | Y | Agent card generation/serving works when `--a2a` is enabled. |
| A2A | RPC routes (`message/send`, `message/stream`, `tasks/get`, `tasks/cancel`, `tasks/resubscribe`, push config set/get) | Y | JSON-RPC + REST-style task routes are implemented and tested. |
| A2A | Push callback delivery reliability | Y | Push notifications use persistent SQLite queue + retry/backoff + startup/background draining. |
| Extra plugins | Dynamic plugin loading via class specs | Y | Supports built-ins, registered factories, `package:...:Class`, absolute file specs, and dotted class paths. |
| Telemetry | `SqliteSpanExporter` physical sqlite persistence | Y | Spans are persisted in real sqlite tables and are queryable via debug trace endpoints. |
| Tools runtime | Unified bootstrap registration API | Y | `configureToolRuntimeBootstrap(...)` / `resetToolRuntimeBootstrap(...)` provide one-place wiring for BigQuery/Bigtable/Spanner/Toolbox/audio adapters. |

### Partial / Not Yet Supported

| Area | Feature | Status | Notes |
| --- | --- | --- | --- |
| Sessions | `mysql://` TLS/SSL transport options | Y | Uses `mysql_client_plus`; supports TLS flags (`secure`/`ssl`/`tls`, `sslmode=require`), CA file (`ssl_ca_file`), client cert/key (`ssl_cert_file` + `ssl_key_file`), optional verify toggle (`ssl_verify=false`), and auto secure-retry for auth plugins that require TLS (unless explicitly disabled). |
| Sessions | `VertexAiSessionService` remote persistence compatibility | Y | Service uses Vertex Session API client paths (`create/get/list/delete`, events append/list) with HTTP transport. |
| Artifacts | `gs://` default artifact backend | Y | `GcsArtifactService` now includes built-in live HTTP/auth providers; custom providers remain optional. |
| Tools runtime | BigQuery default client | Y | Bundled REST client is available by default (token required via credentials/env/gcloud ADC). |
| Tools runtime | Bigtable default clients | Y | Bundled REST admin/data clients are available by default (token required via credentials/env/gcloud ADC). |
| Tools runtime | Spanner default client | Y | Bundled REST client is available by default (token required via credentials/env/gcloud ADC). |
| Tools runtime | Spanner embedder runtime | Y | Built-in Vertex AI embedding runtime is available (project/location + token required); custom embedder injection remains optional. |
| Tools runtime | BigQuery Data Insights default provider | Y | Built-in HTTP stream provider is available; injection is optional for customization/tests. |
| Tools runtime | Discovery Engine search without handler | Y | Uses built-in Discovery Engine API HTTP path when `searchHandler` is not provided. |
| Tools runtime | Toolbox integration without delegate | Y | Built-in native toolbox HTTP delegate is available (`/api/toolset/*`, `/api/tool/*/invoke`); custom delegate registration is still supported. |
| Secrets | Secret Manager access without fetcher | Y | Built-in Secret Manager HTTP fetcher is available; injection is optional. |
| Audio | Speech transcription runtime bootstrap | Partial | Recognizer is still required, but can now be provided per instance or globally via `AudioTranscriber.registerDefaultRecognizer(...)`. |
| OpenAPI | External multi-file `$ref` resolution | N | Parser throws on external refs (`External references not supported`). |
| Spanner | PostgreSQL vector/ANN support | Partial | ANN is unsupported for PostgreSQL path; feature set is partially constrained. |

## Installation

### Stable Release (Recommended)

```bash
dart pub add adk_dart
```

If you prefer a shorter import path, use the facade package:

```bash
dart pub add adk
```

### Development Version

Use a git dependency in your `pubspec.yaml`:

```yaml
dependencies:
  adk_dart:
    git:
      url: https://github.com/adk-labs/adk_dart.git
      ref: main
```

Then:

```bash
dart pub get
```

## Gemini API Key Setup

ADK Dart recommends the following primary environment variable name:

- `GOOGLE_API_KEY` (recommended)

ADK Dart also accepts `GEMINI_API_KEY` as a compatibility alias.

### Option A: Gemini API mode (default)

Create a `.env` file (or export env vars in your shell):

```env
GOOGLE_GENAI_USE_VERTEXAI=0
GOOGLE_API_KEY=your_google_api_key
# Optional alias (if both are set, GEMINI_API_KEY is used first):
# GEMINI_API_KEY=your_google_api_key
```

### Option B: Vertex AI mode

```env
GOOGLE_GENAI_USE_VERTEXAI=1
GOOGLE_CLOUD_PROJECT=your-gcp-project-id
GOOGLE_CLOUD_LOCATION=us-central1
GOOGLE_API_KEY=your_google_api_key
```

Notes:

- `adk create ...` generates `.env` with `GOOGLE_API_KEY="YOUR_API_KEY"` by
  default.
- `adk` CLI loads `.env` automatically unless
  `ADK_DISABLE_LOAD_DOTENV=1` (or `true`) is set.

## MCP (Model Context Protocol)

ADK Dart includes MCP support and now ships protocol primitives as a dedicated
package:

- `packages/adk_mcp`: MCP transport/lifecycle core for Dart
- `adk_dart` MCP layer: ADK tool/runtime integration (`McpToolset`,
  `McpSessionManager`, `LoadMcpResourceTool`, `McpInstructionProvider`)

For most users, importing `package:adk_dart/adk_dart.dart` is sufficient.

## Documentation

- Repository: <https://github.com/adk-labs/adk_dart>
- API surface entrypoint: [`lib/adk_dart.dart`](lib/adk_dart.dart)
- Documentation index: [`docs/README.md`](docs/README.md)
- Work-unit logs: [`docs/worklog/`](docs/worklog/)
- Reference knowledge: [`docs/knowledge/`](docs/knowledge/)
- Python compatibility status tracker: [`docs/python_parity_status.md`](../docs/python_parity_status.md)
- Python-to-Dart implementation manifest: [`docs/python_to_dart_parity_manifest.md`](../docs/python_to_dart_parity_manifest.md)

## Feature Highlight

Runnable feature-highlight sample (Google Search single agent + coordinator
multi-agent):

- `example/feature_highlight_agents.dart`

### Define a single agent

```dart
import 'package:adk_dart/adk_dart.dart';

class EchoModel extends BaseLlm {
  EchoModel() : super(model: 'echo');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String userText = request.contents.isEmpty
        ? ''
        : request.contents.last.parts
              .where((Part part) => part.text != null)
              .map((Part part) => part.text!)
              .join(' ');

    yield LlmResponse(content: Content.modelText('echo: $userText'));
  }
}

Future<void> main() async {
  final Agent agent = Agent(name: 'echo_agent', model: EchoModel());
  final InMemoryRunner runner = InMemoryRunner(agent: agent);

  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'user_1',
    sessionId: 'session_1',
  );

  await for (final Event event in runner.runAsync(
    userId: 'user_1',
    sessionId: session.id,
    newMessage: Content.userText('hello'),
  )) {
    print(event.content?.parts.first.text ?? '');
  }
}
```

### Define a multi-agent system

```dart
import 'package:adk_dart/adk_dart.dart';

class StubModel extends BaseLlm {
  StubModel() : super(model: 'stub');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('done'));
  }
}

void main() {
  final Agent greeter = Agent(
    name: 'greeter',
    model: StubModel(),
    instruction: 'Handle greetings.',
  );

  final Agent worker = Agent(
    name: 'worker',
    model: StubModel(),
    instruction: 'Handle execution tasks.',
  );

  final Agent coordinator = Agent(
    name: 'coordinator',
    model: StubModel(),
    instruction: 'Route requests to sub-agents.',
    subAgents: <BaseAgent>[greeter, worker],
  );

  // Use coordinator with Runner / InMemoryRunner.
  print(coordinator.name);
}
```

### Development CLI and Web UI

```bash
dart pub global activate adk_dart
adk create my_agent
cd my_agent
adk run .
adk web --port 8000 .
```

`adk web` starts a local development server and UI at
`http://127.0.0.1:8000`.

## Test

```bash
dart test
dart analyze
```

## Contributing

Issues and pull requests are welcome:

- Issues: <https://github.com/adk-labs/adk_dart/issues>
- Repository: <https://github.com/adk-labs/adk_dart>

## License

This project is licensed under Apache 2.0. See [LICENSE](LICENSE).
