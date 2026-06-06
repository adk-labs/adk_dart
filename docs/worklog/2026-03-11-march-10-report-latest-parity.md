# March 10 Report Latest Parity

- Date: 2026-03-11
- Source range: `ref/adk-python` `9d155177..0ad4de73`
- Report baseline: `reports/adk-python/2026-03-10.md`

## Work Unit 1: Auth Provider Registry and Runner Session Config

- Added pluggable auth provider surface:
  - `BaseAuthProvider`
  - `AuthProviderRegistry`
  - `CredentialManager.registerAuthProvider(...)`
- `CredentialManager` now checks registered auth providers before the standard
  credential exchange / refresh flow.
- Added `RunConfig.getSessionConfig`.
- Threaded `getSessionConfig` through `Runner.runAsync`, `runLive`,
  `rewindAsync`, and `runDebug`.

## Work Unit 2: OpenAPI Preserve Property Names and SaveFiles Ordering

- Added `preservePropertyNames` to the OpenAPI toolset/parser path.
- Preserves original property names when requested while still sanitizing
  reserved identifiers.
- Updated `SaveFilesAsArtifactsPlugin` ordering:
  - stage artifact delta into session state during `onUserMessageCallback()`
  - flush to `eventActions.artifactDelta` during `beforeAgentCallback()`
- This matches the ADK Web UI artifact panel dependency on state-first updates.

## Work Unit 3: LiteLLM and Telemetry

- LiteLLM now:
  - maps `finish_reason=length` to `MAX_TOKENS`
  - emits `errorCode` / `errorMessage` for non-stop finishes
  - extracts reasoning token counts into `usageMetadata.thoughtsTokenCount`
- Telemetry now emits:
  - `gen_ai.usage.experimental.reasoning_tokens_limit`
  - `gen_ai.usage.experimental.reasoning_tokens`
  - `gen_ai.usage.experimental.system_instruction_tokens`

## Work Unit 4: MCP UI Widgets

- Added `UiWidget` and `EventActions.renderUiWidgets`.
- Added `Context.renderUiWidget(...)`.
- `McpBaseTool` now carries `meta`, visibility hints, and MCP App resource URI.
- `McpTool` emits MCP UI widget actions when MCP tool metadata declares an app
  resource URI.
- Persisted `renderUiWidgets` through:
  - function-flow event merging
  - SQLite session persistence
  - Vertex AI session persistence
  - dev web server legacy JSON conversion

## Work Unit 5: Optimize CLI and Local Eval Sampler

- Added `LocalEvalSamplerConfig` and `LocalEvalSampler`.
- Added JSON config parsing for `GepaRootAgentPromptOptimizerConfig`.
- Added `adk optimize` command:
  - `adk optimize <agent_dir> --sampler_config_file_path ...`
  - optional `--optimizer_config_file_path`
  - optional `--print_detailed_results`
- The CLI now wires local eval sets into the existing GEPA optimizer.

## Work Unit 6: BigQuery March 10 Tail

- Updated Gemini Data Analytics endpoint from `v1alpha` to `v1beta`.
- BigQuery analytics view refresh now treats concurrent conflict errors as
  non-fatal and continues startup/manual refresh flows.

## Verification

- Changed-file `dart analyze`: clean
- Passed:
  - `test/auth_provider_registry_test.dart`
  - `test/credential_manager_test.dart`
  - `test/runner_session_config_test.dart`
  - `test/openapi_spec_parser_parity_test.dart`
  - `test/save_files_as_artifacts_plugin_test.dart`
  - `test/models_parity_batch2_test.dart`
  - `test/features_telemetry_parity_test.dart`
  - `test/context_tool_flow_test.dart`
  - `test/mcp_resource_and_tool_test.dart`
  - `test/dev_cli_extended_commands_test.dart`
  - `test/bigquery_agent_analytics_plugin_parity_test.dart`
  - `test/bigquery_parity_test.dart`
  - `test/session_persistence_services_test.dart -n "persists renderUiWidgets"`

## Notes

- Sample-agent-only change `a86aa8b0` was not ported because it does not change
  the Dart runtime/library surface.
- `ffe97ec5` (`gen_ai.agent.version`) had already been reflected earlier and is
  not duplicated here.
