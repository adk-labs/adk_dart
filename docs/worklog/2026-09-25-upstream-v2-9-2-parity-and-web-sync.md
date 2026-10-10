# 2026-09-25 Upstream `adk-python` v2.9.2 Parity (Batches 1 & 2) and `adk-web` Sync Worklog

## Overview
This worklog records the `2026-09-19` and `2026-09-25` parity work units (`0811a32`, `5f84103`, `19a030e`), porting all `adk-python` v2.9.2 runtime features, security hardening, and `adk-web` browser bundle updates.

---

## 1. Upstream `adk-python` v2.9.2 Batch 1 (`0811a32`)
- **Non-Blocking Live Function Calls (`ToolBehavior`)**: Added `ToolBehavior` enum (`blocking`, `nonBlocking`) on `BaseTool` and wired non-blocking background tool execution in Live flows.
- **Cooperative Cancellation (`AbortSignal`)**: Added `AbortSignal` support to `InvocationContext` and `Context` (`abort()`) for cooperative cancellation of running invocations.
- **Strict Tool Confirmation Check**: Enforced strict boolean confirmation checking with default user hints in `RequestConfirmationLlmRequestProcessor` and `functions.dart`.
- **Skill Lifecycle & Eager Discovery**: Added skill lifecycle modes (`persistent`, `bounded`, `ephemeral`) and eager skill discovery mode in `SkillToolset`.
- **MCP Session Termination Recovery**: Automatically discards stale MCP sessions on server-side termination errors (`-32600` or HTTP `404`).
- **Session Commit & Rewind State Delta Filtering**: Added `commitEventToSession` API on `BaseSessionService` and ignored temporary (`temp:`) state keys when computing rewind state deltas.
- **Evaluation Validation**: Added `numSamples < 1` validation on `JudgeModelOptions`.

## 2. Upstream `adk-python` v2.9.2 Batch 2 (`5f84103`)
- **`InvocationNotFoundError`**: Added `InvocationNotFoundError` (extending `NotFoundError` and implementing `ArgumentError`) thrown during `Runner.rewindAsync` when the target invocation ID is missing.
- **Artifact Reference Recursion Guard**: Enforced `maxArtifactReferenceDepth = 5` across `InMemoryArtifactService`, `GcsArtifactService`, and `artifact_util.dart` to prevent circular reference loops.
- **MCP Description Fencing & Client Headers**:
  - Standardized MCP client info as `'google-adk'` and merged lowercase `user-agent` / tracking headers.
  - Added `_fencing.dart` (`lib/src/flows/llm_flows/_fencing.dart`) to wrap untrusted MCP tool descriptions with fencing markers and system preamble injection.
- **`SkillToolset` Dynamic Revalidation**: Added `revalidateSkills` support and conditional hiding of `run_skill_script` when no skill defines scripts.
- **Parallel Tool State Merge & Integer Coercion**:
  - Preserved latest state writes across parallel tool calls using deep equality comparison in `functions.dart`.
  - Coerced whole `double` values (e.g. `3.0`) to `int` for `int` and `List<int>` parameters in `FunctionTool`.
- **Log Redaction & Workflow Multi-Target `DEFAULT_ROUTE`**:
  - Added `redactFileUriForLog` in `LiteLlm` to redact signed query parameters from logged URLs.
  - Allowed `DEFAULT_ROUTE` in `Workflow` to fan out to multiple target nodes simultaneously.

## 3. Runtime Config, Auth Compaction & Search Agent Sync (`19a030e`)
- Synced latest `adk-web` browser bundle (`main-HGOSGOEQ.js`) and served dynamic `/assets/config/runtime-config.json` from `web_server.dart`.
- Filtered internal auth/compaction events in `LlmEventSummarizer` and `contents.dart`.
- Updated `GoogleSearchAgentTool` instructions to match upstream `adk-python`.

---

## Verification
- Added `test/upstream_v2_9_2_parity_test.dart` and `test/upstream_v2_9_2_batch2_parity_test.dart`.
- All core and CLI server tests passing with 0 analyzer issues.
