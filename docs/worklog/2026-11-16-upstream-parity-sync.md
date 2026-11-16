# 2026-11-16 Upstream Parity Sync (`2026.11.16`)

## Upstream Ranges Synced
- **`adk-python`**: `287c0b0e65899b0060efd5672c8f419c1119530d` -> `c6586f19ab8a2bb8b53e70041633b10858d9902e`
- **`adk-web`**: `969cee92b7e249f4b66c3de1f2d354ab012fc0ce` (already up to date)

## Key Ported Commits
1. **`d05e48203` — Show working directory based on `working_dir` instead of `is_initialized`**:
   - `BaseEnvironment.workingDir` defaults to `null`; `LocalEnvironment` reports `null` until `initialize()` creates a temporary workspace and resets on `close()`; sandbox environments (`DaytonaEnvironment`, `E2BEnvironment`, `OpenSandboxEnvironment`, `AgentEngineEnvironment`) expose fixed workspace paths before `initialize()`.
   - `workingDirOrNone`, `EnvironmentToolset`, and `SkillToolset` inject working/skills folder instructions whenever `workingDir` is known without initializing sandboxes.
2. **`c6586f19a` — Enable `DYNAMIC_INSTRUCTION_ROUTING` by default**:
   - Enabled `FeatureName.dynamicInstructionRouting` (`defaultOn: true`) and synced missing `FeatureName` entries.
   - Wired `LlmRequest.appendDynamicInstructions`, `insertTransientUserContent`, `labelDynamicInstruction`, and `DynamicInstructionsLlmRequestProcessor` across `BaseLlmFlow`, `LoadArtifactsTool`, `LoadMcpResourceTool`, and `PreloadMemoryTool`.
