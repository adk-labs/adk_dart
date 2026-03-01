# Agent Development Kit (ADK) for Dart

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![pub package](https://img.shields.io/pub/v/adk_dart.svg)](https://pub.dev/packages/adk_dart)
[![Package Sync](https://github.com/adk-labs/adk_dart/actions/workflows/package-sync.yml/badge.svg)](https://github.com/adk-labs/adk_dart/actions/workflows/package-sync.yml)

ADK Dart is an open-source, code-first Dart framework for building and running
AI agents with modular runtime primitives, tool orchestration, and MCP
integration.

It is a Dart port of ADK concepts with a focus on practical runtime parity and
developer ergonomics.

---

## 🔥 What's New

- **MCP Protocol Core Package**: Added `packages/adk_mcp` and moved MCP
  streamable HTTP protocol handling into a dedicated package.
- **MCP Spec Hardening**: Improved MCP lifecycle and transport behavior
  (session recovery, SSE response matching by request id, cancellation
  notifications, capability-aware RPC usage).
- **Parity Expansion**: Added broader runtime parity coverage across sessions,
  toolsets, and model/tool integration layers in the `0.1.x` line.

## ✨ Key Features

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

## 📊 Feature Support Matrix (Current)

This matrix is rebuilt from a fresh source audit plus targeted runtime tests
(`dev_web_server`, `cli_adk_web_server`, `mcp_http`, `mcp_tooling`,
`session_persistence`) rather than legacy parity docs.

Status legend:

- `✅` Supported
- `⚠️` Partial / integration required
- `❌` Not supported yet

### Supported / Working

| Area | Feature | Status | Notes |
| --- | --- | --- | --- |
| Core runtime | Agent execution (`Runner`, `InMemoryRunner`) | ✅ | Event-driven run / rewind / live paths are implemented and tested. |
| Sessions | `memory://`, local sqlite, `postgresql://`, `mysql://` session persistence | ✅ | SQLite(local FFI) + network backends are wired through `DatabaseSessionService`; live Postgres/MySQL roundtrip tests are included (env-gated). |
| Artifacts | `memory://` and local file artifacts | ✅ | Artifact CRUD/version APIs are wired through web + runner flows. |
| MCP | Streamable HTTP + stdio tool/resource/prompt flows | ✅ | `adk_mcp` + `McpSessionManager` cover initialize/call/pagination/notifications. |
| CLI | `create`, `run`, `web`, `api_server`, `deploy` | ✅ | Parsed and executed through `lib/src/dev/cli.dart`; `deploy` supports dry-run and real command execution path. |
| CLI run | `--save_session`, `--resume`, `--replay`, `--message` | ✅ | Session snapshot import/export and replay paths are implemented. |
| Web server | `/dev-ui` static hosting and config endpoint | ✅ | Bundled UI serving and SPA fallback are implemented. |
| Web server | `/health`, `/version`, `/list-apps`, `/run`, `/run_sse`, `/run_live` | ✅ | Core dev runtime API works and is covered by web tests. |
| Web server | Python-style session/memory/artifact routes | ✅ | `/apps/{app}/users/{user}/sessions...` CRUD and artifact routes are implemented. |
| Web server | Debug/Eval/Trace parity families | ✅ | Includes `/debug/trace/*`, `/apps/{app}/metrics-info`, `/apps/{app}/eval-*`, and event graph endpoints. |
| Web options | `allow_origins`, `url_prefix`, `reload`, `reload_agents`, logo, telemetry flags | ✅ | Options are parsed and propagated into runtime/web context. |
| A2A | Agent card endpoints (`/.well-known/agent.json`, `/a2a/<app>/.well-known/agent.json`) | ✅ | Agent card generation/serving works when `--a2a` is enabled. |
| A2A | RPC routes (`message/send`, `message/stream`, `tasks/get`, `tasks/cancel`, `tasks/resubscribe`, push config set/get) | ✅ | JSON-RPC + REST-style task routes are implemented and tested. |
| A2A | Push callback delivery reliability | ✅ | Push notifications use persistent SQLite queue + retry/backoff + startup/background draining. |
| Extra plugins | Dynamic plugin loading via class specs | ✅ | Supports built-ins, registered factories, `package:...:Class`, absolute file specs, and dotted class paths. |
| Telemetry | `SqliteSpanExporter` physical sqlite persistence | ✅ | Spans are persisted in real sqlite tables and are queryable via debug trace endpoints. |
| Tools runtime | Unified bootstrap registration API | ✅ | `configureToolRuntimeBootstrap(...)` / `resetToolRuntimeBootstrap(...)` provide one-place wiring for BigQuery/Bigtable/Spanner/Toolbox/audio adapters. |

### Partial / Not Yet Supported

| Area | Feature | Status | Notes |
| --- | --- | --- | --- |
| Sessions | `mysql://` TLS/SSL transport options | ✅ | Uses `mysql_client_plus`; supports TLS flags (`secure`/`ssl`/`tls`, `sslmode=require`), CA file (`ssl_ca_file`), client cert/key (`ssl_cert_file` + `ssl_key_file`), optional verify toggle (`ssl_verify=false`), and auto secure-retry for auth plugins that require TLS (unless explicitly disabled). |
| Sessions | `VertexAiSessionService` remote persistence parity | ⚠️ | Current implementation delegates storage to in-memory service. |
| Artifacts | `gs://` default artifact backend | ❌ | Default `GcsArtifactService` live mode needs injected HTTP/auth providers. |
| Tools runtime | BigQuery default client | ⚠️ | No bundled concrete client; inject via `configureToolRuntimeBootstrap(...)` or `setBigQueryClientFactory()`. |
| Tools runtime | Bigtable default clients | ⚠️ | No bundled concrete admin/data clients; inject via bootstrap or `setBigtableClientFactories()`. |
| Tools runtime | Spanner default client + embedder | ⚠️ | No bundled concrete client/embedder; inject via bootstrap or `setSpannerClientFactory()` + `setSpannerEmbedders()`. |
| Tools runtime | BigQuery Data Insights default provider | ❌ | Requires `setBigQueryInsightsStreamProvider()` injection. |
| Tools runtime | Discovery Engine search without handler | ❌ | `DiscoveryEngineSearchTool` requires explicit `searchHandler`. |
| Tools runtime | Toolbox integration without delegate | ⚠️ | Requires delegate wiring; bootstrap supports `toolboxDelegateFactory` registration. |
| Secrets | Secret Manager access without fetcher | ❌ | Requires `setSecretManagerSecretFetcher()` injection. |
| Audio | Speech transcription runtime bootstrap | ⚠️ | Recognizer is still required, but can now be provided per instance or globally via `AudioTranscriber.registerDefaultRecognizer(...)`. |
| OpenAPI | External multi-file `$ref` resolution | ❌ | Parser throws on external refs (`External references not supported`). |
| Spanner | PostgreSQL vector/ANN parity | ⚠️ | ANN is unsupported for PostgreSQL path; feature set is partially constrained. |

## 🚀 Installation

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

## 🔐 Gemini API Key Setup

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

## 🤖 MCP (Model Context Protocol)

ADK Dart includes MCP support and now ships protocol primitives as a dedicated
package:

- `packages/adk_mcp`: MCP transport/lifecycle core for Dart
- `adk_dart` MCP layer: ADK tool/runtime integration (`McpToolset`,
  `McpSessionManager`, `LoadMcpResourceTool`, `McpInstructionProvider`)

For most users, importing `package:adk_dart/adk_dart.dart` is sufficient.

## 📚 Documentation

- Repository: <https://github.com/adk-labs/adk_dart>
- API surface entrypoint: [`lib/adk_dart.dart`](lib/adk_dart.dart)
- Parity status tracker: [`docs/python_parity_status.md`](../docs/python_parity_status.md)
- Parity manifest: [`docs/python_to_dart_parity_manifest.md`](../docs/python_to_dart_parity_manifest.md)

## 🏁 Feature Highlight

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
adk run my_agent
adk web --port 8000 my_agent
```

`adk web` starts a local development server and UI at
`http://127.0.0.1:8000`.

## 🧪 Test

```bash
dart test
dart analyze
```

## 🤝 Contributing

Issues and pull requests are welcome:

- Issues: <https://github.com/adk-labs/adk_dart/issues>
- Repository: <https://github.com/adk-labs/adk_dart>

## 📄 License

This project is licensed under Apache 2.0. See [LICENSE](LICENSE).
