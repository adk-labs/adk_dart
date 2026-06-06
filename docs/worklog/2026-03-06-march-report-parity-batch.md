# March Report Parity Batch

- Date: 2026-03-06
- Scope: `reports/adk-python/2026-03-03.md`, `2026-03-04.md`, `2026-03-05.md`
- Goal: close March Python parity gaps that were still missing in Dart and keep runtime behavior aligned.

## Task Unit 1: temp-scoped session state visibility

- Python reference: `2780ae28` (`temp-scoped state now visible to subsequent agents in same invocation`)
- Problem:
  - Dart trimmed `temp:` keys during append and never exposed them to later agents/tools in the same invocation.
  - This caused state visibility gaps even though the keys were intended to remain transient only, not persisted.
- Change:
  - Live session state now keeps `temp:` keys for the current invocation.
  - Persisted event/state payloads still strip `temp:` keys before writing to SQLite, network DB, or Vertex session storage.
- Files:
  - `lib/src/sessions/base_session_service.dart`
  - `lib/src/sessions/sqlite_session_service.dart`
  - `lib/src/sessions/network_database_session_service.dart`
  - `lib/src/sessions/vertex_ai_session_service.dart`
  - `test/session_service_test.dart`
  - `test/session_persistence_services_test.dart`

## Task Unit 2: filter non-agent directories from `listAgents()`

- Python reference: `3b5937f0`
- Problem:
  - Dart listed every non-hidden directory under the agents root, even when it did not contain a loadable agent.
- Change:
  - `listAgents()` now filters directories using the same loadability criteria as `loadAgent()`.
  - Single-app roots now expose the configured app alias from `adk.json` when applicable.
- Files:
  - `lib/src/cli/utils/agent_loader.dart`
  - `test/cli_agent_loader_test.dart`

## Task Unit 3: telemetry `gen_ai.agent.version`

- Python reference: `a61ccf36`
- Problem:
  - Dart emitted `gen_ai.agent.name` and related span attributes, but omitted `gen_ai.agent.version`.
- Change:
  - Added `gen_ai.agent.version` to agent invocation spans and common inference attributes.
- Files:
  - `lib/src/telemetry/tracing.dart`
  - `test/features_telemetry_parity_test.dart`

## Task Unit 4: LiteLLM reasoning field parsing

- Python reference: `94684874`
- Problem:
  - Dart LiteLLM parsing ignored `reasoning` payloads and therefore lost model thought content that Python preserved.
- Change:
  - LiteLLM parsing now converts both `reasoning_content` and `reasoning` payloads into thought parts.
  - Duplicate reasoning text is de-duplicated.
- Files:
  - `lib/src/models/lite_llm.dart`
  - `test/models_parity_batch2_test.dart`

## Task Unit 5: Bigtable cluster metadata tools

- Python reference: `34c560e6`
- Problem:
  - Dart Bigtable metadata coverage stopped at instances and tables.
- Change:
  - Added cluster metadata interfaces in the Bigtable admin client.
  - Added `list_clusters` and `get_cluster_info` metadata tools.
  - Added parity coverage in Bigtable metadata/toolset tests and runtime bootstrap fakes.
- Files:
  - `lib/src/tools/bigtable/client.dart`
  - `lib/src/tools/bigtable/metadata_tool.dart`
  - `lib/src/tools/bigtable/bigtable_toolset.dart`
  - `test/bigtable_parity_test.dart`
  - `test/tools_runtime_bootstrap_test.dart`

## Verification

- Targeted tests passed:
  - `dart test test/session_service_test.dart test/session_persistence_services_test.dart test/cli_agent_loader_test.dart test/features_telemetry_parity_test.dart test/models_parity_batch2_test.dart test/bigtable_parity_test.dart`
  - `dart test test/tools_runtime_bootstrap_test.dart test/bigtable_parity_test.dart`
- Changed-file analysis passed:
  - `dart analyze lib/src/sessions/base_session_service.dart lib/src/sessions/sqlite_session_service.dart lib/src/sessions/network_database_session_service.dart lib/src/sessions/vertex_ai_session_service.dart lib/src/cli/utils/agent_loader.dart lib/src/telemetry/tracing.dart lib/src/models/lite_llm.dart lib/src/tools/bigtable/client.dart lib/src/tools/bigtable/metadata_tool.dart lib/src/tools/bigtable/bigtable_toolset.dart test/session_service_test.dart test/session_persistence_services_test.dart test/cli_agent_loader_test.dart test/features_telemetry_parity_test.dart test/models_parity_batch2_test.dart test/bigtable_parity_test.dart test/tools_runtime_bootstrap_test.dart`
- Repo-wide `dart analyze` still reports pre-existing unrelated errors in:
  - `packages/adk_mcp/test/mcp_stdio_client_test.dart`
  - `test/skill_toolset_parity_test.dart`
  - plus existing informational diagnostics including `tool/_doc_scan.dart`
