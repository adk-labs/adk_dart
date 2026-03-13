# 2026-03-13 Conformance Replay Runtime Parity

## Scope
- Close the remaining conformance replay runtime gap so `adk conformance test --mode replay` reuses recorded LLM and tool interactions instead of re-running the live runtime.
- Align YAML fixture round-tripping so generated recordings and sessions can be loaded back without structural drift.

## Work Units

### 1. Runtime replay interception
- Added `ConformanceRecordingsPlugin` to capture LLM requests/responses and tool calls/responses into `generated-recordings.yaml` and `generated-recordings-sse.yaml`.
- Added `ConformanceReplayPlugin` to load recorded interactions and short-circuit tool execution during replay.
- Added `ConformanceReplayLlm` and wired `BaseLlmFlow` to swap in the replay model when `_adk_replay_config` is present.
- Wired the built-in conformance plugins into the dev web server so replay works without extra manual plugin setup.

### 2. CLI recording and replay parity
- Switched `adk conformance record` to let runtime plugins own recordings output instead of deriving recordings from emitted event dumps.
- Preserved sanitized session events in generated session fixtures so replay mode can compare recorded vs actual event streams.
- Normalized replay request comparison to ignore empty `partial_args` defaults that do not affect behavior.

### 3. YAML round-trip correctness
- Fixed the lightweight YAML decoder to accept bare `-` list items.
- Preserved blank lines in literal blocks.
- Fixed multiline scalar emission to use `|-` when the source string does not end with a newline, preventing replay drift from synthetic trailing newlines.

### 4. Regression coverage
- Added an end-to-end CLI test that records fixtures, forces the live model/tool to fail, and verifies replay still passes by consuming recorded interactions.

## Files
- `lib/src/cli/plugins/conformance_recordings_schema.dart`
- `lib/src/cli/plugins/conformance_recordings_plugin.dart`
- `lib/src/cli/plugins/conformance_replay_plugin.dart`
- `lib/src/models/conformance_replay_llm.dart`
- `lib/src/dev/cli.dart`
- `lib/src/dev/web_server.dart`
- `lib/src/flows/llm_flows/base_llm_flow.dart`
- `lib/src/utils/yaml_utils.dart`
- `test/dev_cli_extended_commands_test.dart`

## Verification
- `dart analyze lib/src/cli/plugins/conformance_recordings_schema.dart lib/src/cli/plugins/conformance_recordings_plugin.dart lib/src/cli/plugins/conformance_replay_plugin.dart lib/src/models/conformance_replay_llm.dart lib/src/dev/cli.dart lib/src/dev/web_server.dart lib/src/flows/llm_flows/base_llm_flow.dart lib/src/utils/yaml_utils.dart test/dev_cli_extended_commands_test.dart`
- `dart test test/dev_cli_extended_commands_test.dart test/cli_conformance_utils_test.dart`
