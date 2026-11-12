---
name: adk-dart-setup
description: >-
  Sets up ADK Dart & Flutter projects, selects the right package (adk, adk_dart,
  flutter_adk, adk_mcp, adk_litertlm) and domain entrypoint barrel, configures
  Gemini / Vertex AI / local LLM credentials, runs the adk CLI toolchain
  (create, run, web, api_server, eval, eval_set, optimize, generate_agent_card,
  deploy, conformance, migrate), and executes contributor build, analyze, and
  test workflows. Use when asked to install or configure ADK in a Dart or
  Flutter project, run adk CLI commands, set up API keys, or run repository
  tests and static analysis. Don't use for writing agent logic or workflows
  (use adk-dart-agent-builder) or building Flutter UI widgets (use
  flutter-adk-ui-builder).
---

# ADK Dart & Flutter Setup

Checked against `adk_dart` `2026.11.12` (`adk-python` `2.14.0` baseline).

## 1. Choosing the Right Package & Import

| Use Case | Package | Recommended Import |
| --- | --- | --- |
| Dart VM / Server / CLI app (full runtime + CLI binary) | `adk` | `import 'package:adk/adk.dart';` |
| Dart VM / Server app (core runtime SDK) | `adk_dart` | `import 'package:adk_dart/adk_dart.dart';` |
| Selective domain imports (faster IDE completion, minimal namespace) | `adk_dart` | `import 'package:adk_dart/agents.dart';` (or `workflow.dart`, `evaluation.dart`, `tools.dart`, `models.dart`, `sessions.dart`, `integrations.dart`, `a2a.dart`, `telemetry.dart`) |
| Cross-platform / Web-safe Dart runtime only (no Flutter UI) | `adk_dart` | `import 'package:adk_dart/adk_core.dart';` |
| Flutter app (iOS, Android, Web/WASM, macOS, Windows, Linux) + Turnkey UI Kit | `flutter_adk` | `import 'package:flutter_adk/flutter_adk.dart';` |
| Standalone MCP client/server protocol primitives | `adk_mcp` | `import 'package:adk_mcp/adk_mcp.dart';` |
| On-device LiteRT-LM / Gemini Nano acceleration | `adk_litertlm` | `import 'package:adk_litertlm/adk_litertlm.dart';` |

### Adding Dependencies

For Dart VM / backend projects:

```bash
dart pub add adk_dart
# Or for the unified facade + CLI executable:
dart pub add adk
```

For Flutter apps:

```bash
flutter pub add flutter_adk
```

---

## 2. Environment Variables & Credentials

### Option A: Gemini Developer API (Default)

Set `GOOGLE_API_KEY` (recommended) or `GEMINI_API_KEY` in `.env` or shell environment:

```env
GOOGLE_GENAI_USE_VERTEXAI=0
GOOGLE_API_KEY=your_google_api_key
```

### Option B: Google Cloud Vertex AI

```env
GOOGLE_GENAI_USE_VERTEXAI=1
GOOGLE_CLOUD_PROJECT=your-gcp-project-id
GOOGLE_CLOUD_LOCATION=us-central1
```

Authenticate via Application Default Credentials (`gcloud auth application-default login`) or `GOOGLE_APPLICATION_CREDENTIALS`.

### Option C: Third-Party & Local LLMs (`AnthropicLlm`, `LiteLlm`)

- **Anthropic Claude**: Set `ANTHROPIC_API_KEY` and use `AnthropicLlm(model: 'claude-3-7-sonnet-latest')`.
- **OpenAI / Ollama / LM Studio / Groq / DeepSeek**: Use `LiteLlm(model: 'ollama_chat/gemma2:2b', baseUrl: 'http://localhost:11434/v1')` or set `OPENAI_API_KEY`.

---

## 3. `adk` CLI Toolchain

Activate globally or run via `dart run adk`:

```bash
dart pub global activate adk
```

| Command | Example | Purpose |
| --- | --- | --- |
| `adk create` | `adk create my_agent --type CODE` | Scaffolds a new agent project (`CODE`, `CONFIG`, `BASIC`, `WORKFLOW`). |
| `adk run` | `adk run . -m "Hello"` | Runs an agent interactively or executes a single query (`--jsonl`, `--save_session`, `--resume`, `--replay`, `--state`). |
| `adk web` | `adk web --port 8000 .` | Starts the local ADK Dev Web Server + interactive Web UI (`http://127.0.0.1:8000`). |
| `adk api_server` | `adk api_server --port 8000 --a2a .` | Starts the headless REST/SSE/A2A API server (`--with_ui`, `--trigger_sources pubsub,eventarc`). |
| `adk eval` | `adk eval . eval_set.json --num_runs 3` | Evaluates an agent against eval sets (supports multi-run `pass@k` and `pass^k`). |
| `adk eval_set` | `adk eval_set create . my_set` | Creates or populates evaluation sets (`create`, `add_eval_case`, `generate_eval_cases`). |
| `adk optimize` | `adk optimize . --eval_set_file eval.json` | Optimizes root agent instructions against a local evaluation set. |
| `adk generate_agent_card` | `adk generate_agent_card . -o agent.json` | Generates an A2A `AgentCard` JSON file from an agent definition. |
| `adk deploy` | `adk deploy cloud_run . --project my-proj` | Deploys an agent to `cloud_run`, `docker`, `agent_engine`, or `gke`. |
| `adk conformance` | `adk conformance test .` | Runs ADK conformance recording or verification suites (`record`, `test`). |
| `adk migrate session` | `adk migrate session --source_uri ...` | Migrates sessions between storage backends. |
| `adk doctor` | `adk doctor` | Prints SDK, OS, and environment diagnostics. |

> **Note on Dynamic Agent Loading in Dart**: When `adk web` or `adk run` points at a Dart agent directory containing `agent.dart` (defining `rootAgent`), the CLI spawns a Dart VM subprocess host to bridge HTTP/SSE/eval requests dynamically since Dart does not have Python's `importlib.import_module` in precompiled binaries.

---

## 4. Contributor Build, Analyze & Test Commands

When working inside the `adk_dart` monorepo, always verify static analysis and tests across affected packages:

```bash
# 1. Core SDK (adk_dart)
dart analyze lib test
dart test

# 2. CLI & Dev Web Server (packages/adk)
cd packages/adk
dart analyze lib bin test
dart test

# 3. Flutter UI Kit (packages/flutter_adk)
cd ../flutter_adk
flutter analyze lib test
flutter test

# 4. MCP & LiteRT-LM packages
cd ../adk_mcp && dart analyze lib test && dart test
cd ../adk_litertlm && dart analyze lib test && dart test
```
