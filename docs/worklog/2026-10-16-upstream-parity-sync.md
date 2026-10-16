# Upstream Multi-SDK Parity Sync & Enhancements (2026-10-16)

## Overview
Comprehensive synchronization across all upstream ADK repositories (`adk-python`, `adk-go`, `adk-java`, `adk-js`, `adk-kotlin`, `adk-web`) bringing `adk_dart` and `packages/adk` to complete parity.

---

## Unit 1: Core Runtime Updates
- **BaseAgent Artifact Delta Recording (`019387c62`)**:
  - In `lib/src/agents/base_agent.dart`: Updated callback event generation so `actions.artifactDelta` from `beforeAgentCallback` and `afterAgentCallback` produces an `Event` even when `state.hasDelta()` is false.
- **AgentTool RunConfig Forwarding (`6ed5dd08`)**:
  - In `lib/src/tools/agent_tool.dart`: Forwarded `runConfig: invocationContext.runConfig` when invoking `runner.runAsync(...)`, ensuring the model-call budget (`maxLlmCalls`) and runtime configuration bound sub-agent executions identically to the caller.
- **Memory Service `deleteMemory` API (`41e5c7b90`, `2416f660b`)**:
  - `BaseMemoryService`: Added `Future<void> deleteMemory({required String appName, required String userId, String? memoryId})`.
  - `InMemoryMemoryService`: Added `_deletedMemoryIdsByUserKey` tracking to purge deleted events and prevent re-ingestion from subsequent session additions. Added `id: event.id` to `MemoryEntry`.
  - `InvocationContext` and `Context`: Added `deleteMemory({String? memoryId})` delegation.
- **JSON Pointer `$ref` Dereferencing (`59fe93bd0`)**:
  - `lib/src/tools/_gemini_schema_util.dart`: Implemented `_resolveJsonPointer` with URI-fragment parsing, URI unquoting, token unescaping (`~1` -> `/`, `~0` -> `~`), array indexing, supporting both `definitions` and `$defs`, circular reference detection, and defs fallback.
- **Tests**:
  - Added [test/unit1_core_parity_test.dart](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/test/unit1_core_parity_test.dart) covering JSON Pointer resolution and `InMemoryMemoryService.deleteMemory`.
