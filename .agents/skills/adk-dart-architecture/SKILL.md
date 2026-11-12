---
name: adk-dart-architecture
description: >-
  Explains how the ADK Dart & Flutter monorepo and runtime internals fit
  together: BaseNode, Workflow, NodeRunner, Runner, LlmFlow processors,
  Context and Event streams, part / part of modularized subsystems, domain
  entrypoint barrels, Web-safe (adk_core.dart) vs VM (adk_dart.dart) boundaries,
  and adk-python / adk-web parity conventions. Use when answering "how does X
  work" about ADK Dart internals, deciding where a new class or export belongs,
  modifying core runtime files, or porting upstream adk-python / adk-web
  changes. Don't use for assembling an agent from public APIs (use
  adk-dart-agent-builder) or building Flutter UI screens (use
  flutter-adk-ui-builder).
---

# ADK Dart Architecture & Internals

Checked against `adk_dart` `2026.11.12` (`adk-python` `2.14.0` baseline).

## 1. Execution Model Overview

1. **Unified Graph & Agent Hierarchy**:
   - `BaseNode` is the foundational execution unit in ADK 2.0 workflows.
   - `BaseAgent` (and `LlmAgent` / `Agent`, `SequentialAgent`, `ParallelAgent`, `LoopAgent`, `ManagedAgent`, `RemoteA2aAgent`) defines agent execution and can participate directly in `Workflow` graphs or standalone `Runner` invocations.
   - `Workflow` schedules `BaseNode` instances (`FunctionNode`, `AgentNode`, `JoinNode`, dynamic nodes via `ctx.runNode`) along directed edges and conditional routes.
2. **`Runner` & `InvocationContext`**:
   - `Runner` (and `InMemoryRunner`) owns the session lifecycle (`SessionService`, `ArtifactService`, `MemoryService`, `PluginManager`).
   - `runner.runAsync(...)` creates an `InvocationContext`, applies `PluginManager` hooks, streams `Event` objects (`Stream<Event>`), and persists non-partial events to `SessionService`.
3. **`LlmFlow` Request/Response Pipeline (`lib/src/flows/llm_flows/`)**:
   - `AutoFlow` / `SingleFlow` run ordered `LlmRequestProcessor` and `LlmResponseProcessor` stages: instructions, identity, contents/compaction, context cache, tool declarations, code execution, output schema, tool confirmation (`adk_request_confirmation`), auth preflight, and agent transfer (`transfer_to_agent`).

---

## 2. Entrypoint Barrels & Platform Boundaries

| Entrypoint File | Platform Compatibility | Purpose |
| --- | --- | --- |
| `lib/adk_dart.dart` | Dart VM / CLI / Server | Full SDK export surface (includes `dart:io`, `dart:ffi`, `dart:mirrors` integrations). |
| `lib/adk_core.dart` | All Platforms (VM + Flutter Mobile/Desktop + **Flutter Web / WASM**) | Strictly Web-safe subset re-exported by `package:flutter_adk/flutter_adk.dart`. **Never** export `dart:io`, `dart:ffi`, or `dart:mirrors`-dependent libraries here. |
| `lib/agents.dart` | Dart VM | Selective barrel for agents, contexts, runners, flows, planners, and plugins. |
| `lib/workflow.dart` | All Platforms | Selective barrel for ADK 2.0 `Workflow`, `BaseNode`, `WorkflowTool`, `NodeTool`, and replay utilities. |
| `lib/evaluation.dart` | Dart VM | Selective barrel for `AgentEvaluator`, rubric/trajectory/ROUGE evaluators, and `pass@k` / `pass^k` multi-run aggregation. |
| `lib/tools.dart` | Dart VM | Selective barrel for function/agent/MCP/OpenAPI/Google/data tools, skills, and code executors. |
| `lib/models.dart` | All Platforms | Selective barrel for `BaseLlm`, `Gemini`, `AnthropicLlm`, `LiteLlm`, `GemmaLlm`, `ApigeeLlm`, and `LLMRegistry`. |
| `lib/sessions.dart` | Dart VM | Selective barrel for session, artifact, and memory services (`InMemory`, `Sqlite`, `Database`, `MongoDb`, `VertexAi`, `Gcs`). |
| `lib/integrations.dart` | Dart VM | Selective barrel for cloud/third-party integrations (BigQuery, Bigtable, Spanner, Pub/Sub, Slack, Secret Manager, Sandboxes). |
| `lib/a2a.dart` | Dart VM | Selective barrel for Agent-to-Agent (A2A) protocol, executor, converters, and agent card builder. |
| `lib/telemetry.dart` | Dart VM | Selective barrel for OpenTelemetry tracing, `SqliteSpanExporter`, and `BigQueryAgentAnalyticsPlugin`. |

---

## 3. Modularized `part` / `part of` Subsystems

Large subsystems are split into focused `part` files while keeping a single library namespace so private (`_`) members remain shared without leaking into the public API:

- **Workflow Engine (`lib/src/workflow/`)**:
  - `workflow.dart` (Primary library, `Workflow` class & execution loop)
  - `workflow_models_and_context.dart` (`WorkflowContext`, `RequestInput`, `NodeEvent`, status & state models)
  - `workflow_nodes_and_edges.dart` (`BaseNode`, `FunctionNode`, `AgentNode`, `JoinNode`, `Edge`, `Route`)
  - `workflow_execution_helpers.dart` (Replay, checkpointing, DOT graph rendering, schema validation helpers)
- **BigQuery Agent Analytics (`lib/src/plugins/`)**:
  - `bigquery_agent_analytics_plugin.dart` (`BigQueryAgentAnalyticsPlugin` lifecycle hooks & batching queue)
  - `bigquery_agent_analytics_models.dart` (Config, event schemas, workflow node observation models, SQL views)
  - `bigquery_agent_analytics_formatters.dart` (Payload truncation, JSON formatting, trace/span helpers)
- **LiteLLM Multi-Provider Client (`lib/src/models/`)**:
  - `lite_llm.dart` (`LiteLlm` class, HTTP/SSE transport, provider routing)
  - `lite_llm_message_converter.dart` (ADK `Content`/`Part` <-> OpenAI/LiteLLM message & schema conversion)
  - `lite_llm_tool_call_parser.dart` (Streaming delta assembly, tool call extraction, usage parsing)
- **CLI & Dev Web Server (`packages/adk/lib/src/dev/`)**:
  - `cli.dart` + `cli_run_and_web.dart` + `cli_eval_and_optimize.dart` + `cli_conformance_and_migrate.dart`
  - `web_server.dart` + `web_server_session_and_run_routes.dart` + `web_server_eval_and_a2a_routes.dart` + `web_server_assets_and_helpers.dart`

---

## 4. Where Core Concepts Live

| Concept | Path |
| --- | --- |
| `BaseAgent`, `LlmAgent` (`Agent`), `Context`, `InvocationContext`, `RunConfig` | `lib/src/agents/` |
| `Workflow`, `BaseNode`, `JoinNode`, `WorkflowTool`, `NodeTool`, `ReplayManager` | `lib/src/workflow/` |
| `Runner`, `InMemoryRunner` | `lib/src/runners/` |
| `Event`, `EventActions`, `NodePathBuilder`, `applyRewinds` | `lib/src/events/` |
| `BaseLlm`, `LlmRequest`, `LlmResponse`, `Gemini`, `AnthropicLlm`, `LiteLlm`, `toGenerateContentBody` | `lib/src/models/` |
| `BaseTool`, `FunctionTool`, `AgentTool`, `McpToolset`, `OpenAPIToolset`, `SkillToolset`, `ToolSearchToolset` | `lib/src/tools/`, `lib/src/skills/` |
| `Session`, `State`, `InMemorySessionService`, `SqliteSessionService`, `DatabaseSessionService` | `lib/src/sessions/` |
| `AgentEvaluator`, `MultiRunCaseResult`, `pass@k` / `pass^k`, `EvalCaseResultMultiRunAggregator` | `lib/src/evaluation/` |
| `adk` CLI 1:1 Python parity modules (`cli_create`, `cli_deploy`, `cli_eval`, `adk_web_server`) | `packages/adk/lib/src/cli/`, `packages/adk/lib/src/dev/` |
| Flutter M3 Widgets, Controllers, `AdkTheme`, `AdkFormatters`, `AdkEventStreamUtils` | `packages/flutter_adk/lib/src/` |

---

## 5. Upstream Parity Guidelines (`adk-python` & `adk-web`)

When porting commits from `adk-python` (`src/google/adk/`) or `adk-web`:
1. Preserve wire-format JSON keys (`snake_case` or `camelCase` exactly as expected by Gemini REST, A2A, and `adk-web` endpoints).
2. Translate Python keyword-arg conveniences into idiomatic Dart named parameters (e.g., `Event(...)` convenience named parameters, `LlmRequest.toGenerateContentBody()`).
3. If a new symbol is Web-safe (no `dart:io` / `dart:ffi` / `dart:mirrors`), export it in **both** `lib/adk_dart.dart`, `lib/adk_core.dart`, and the appropriate domain barrel (`lib/<domain>.dart`).
4. Add unit tests covering the ported behavior and verify `test/architecture_modularization_test.dart` passes.
