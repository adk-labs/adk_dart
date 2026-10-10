# 2026-10-07 Upstream `adk-python` v2.11.0+ Parity, Examples & Release `2026.10.7` Worklog

## Overview
This worklog documents the `2026-10-07` work unit (`c172c61`) achieving `adk-python` v2.11.0+ parity, updating the built-in Agent Builder Assistant and `adk-web` bundle, adding `examples/19_skills_and_output_artifacts`, and releasing `2026.10.7` across all 5 packages.

---

## 1. Upstream `adk-python` v2.11.0+ Runtime Parity
- **`BaseAgent` Callback Normalization & Resumable Sub-Agents**:
  - Added `canonicalBeforeAgentCallbacks` / `canonicalAfterAgentCallbacks` list normalization on `BaseAgent`.
  - Enabled `BaseAgent.runAsync` and `runLive` to skip directly to active sub-agents when resuming a populated `agentStates` invocation without re-running `beforeAgentCallback`.
  - Added `resetSubAgentStates` so `LoopAgent` and iterative workflows re-enter child agents cleanly on subsequent iterations.
- **`RemoteA2aAgent` & `transfer_to_agent` Description Resolution**:
  - Added `resolvedDescription` on `RemoteA2aAgent` and updated `buildTransferTargetInfo` (`lib/src/flows/llm_flows/agent_transfer.dart`) to prefer resolved A2A agent card descriptions.
- **Sliding-Window Event Compaction (`EventsCompactionConfig`)**:
  - Implemented `runCompactionForSlidingWindow` with `skipTokenCompaction` and exposed `appName` / `userId` on `BaseEventsSummarizer.maybeSummarizeEvents`.
  - Added `LlmRequest.totalTokenCount()`.
- **Skills & Artifact Tooling (`SkillToolset`, `LoadArtifactsTool`, `GcpSkillRegistry`)**:
  - Added `saveOutputArtifacts` to `SkillToolset` (`RunSkillScriptTool`) to automatically persist files generated in `ADK_OUTPUT_DIR` to `ArtifactService`.
  - Added `Part.asSafePartForLlm()` placeholder formatting (`[Binary artifact: ...]`) across `LoadArtifactsTool` and `injectSessionState`.
  - Hardened `injectSessionState` identifier matching so shell variables like `${VAR}` are ignored.
  - Added `SkillSource` and `parseSkillPath` (`local:` vs `gcp:`) in `GcpSkillRegistry`.
- **`BashToolPolicy` & `McpTool` & `PlanReActPlanner`**:
  - Hardened `BashToolPolicy.validateCommand` with shell-tokenized command boundary matching (`_commandMatchesPrefix`) to prevent prefix-confusion bypasses.
  - Updated `McpTool` structured output handling to wrap non-Map JSON values in `{"result": parsed}`.
  - Preserved thought parts on final model responses in `PlanReActPlanner`.
- **Evaluation (`HallucinationsV1Evaluator`, `PerTurnUserSimulatorQualityV1`)**:
  - Added `InvocationEvent.groundingMetadata` and `getGroundingMetadataAsJsonStr`, `Label.partiallyValid` (`0.5`), and whole-word `stopSignal` boundary matching.

## 2. `adk-web` Bundle, Built-in Agents & Examples
- Updated `packages/adk/lib/src/cli/browser/` with `main-FSTPJ7PI.js` and synced `packages/adk/lib/src/cli/built_in_agents/` (`_adk_symbols.py`).
- Added `examples/19_skills_and_output_artifacts` and modernized examples (`04`, `11`, `12`, `13`, `15`, `17`).
- Added `test/upstream_v2_11_0_parity_test.dart` (19 tests) and bumped all packages to `2026.10.7`.
