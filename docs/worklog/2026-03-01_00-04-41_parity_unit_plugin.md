# Plugin Parity Work Unit (2026-03-01 00:04:41)

## Scope
- Dart target:
  - `lib/src/plugins`
  - plugin-callback runtime paths in `lib/src/runners` and `lib/src/flows`
- Python reference:
  - `ref/adk-python/src/google/adk/plugins`

## Parity gaps found
1. `after_run` callback was skipped on runner early-exit path.
2. Global instruction static string path did not inject session state.
3. Instruction processor behavior diverged when static+dynamic instructions coexist.
4. Plugin manager raised generic `StateError` instead of plugin-specific exception type.
5. Debug logging plugin could fail run on file write errors.
6. Context filter plugin swallowed errors without logging.
7. BigQuery analytics plugin differences:
   - default sink behavior mismatch
   - formatter failure handling mismatch
   - `content_parts` logging behavior mismatch

## Implemented changes
1. Plugin manager exception parity
   - Added `PluginManagerException`.
   - Replaced callback/close error `StateError` throws with `PluginManagerException`.
2. Runner callback parity
   - Ensured `runAfterRunCallback` executes even when `before_run` short-circuits.
3. Global instruction parity
   - Changed provider to `FutureOr<String>`.
   - Added `injectSessionState(...)` for static string instructions.
4. Instruction flow parity
   - Applied state-injection rules equivalent to Python.
   - When static instruction exists, dynamic instruction now enters request contents as user content.
5. After-model callback context parity
   - Separated plugin callback context from event-action context to match Python behavior.
6. Debug logging resilience parity
   - Wrapped write path in `try/catch/finally`; always clears invocation state.
7. Context filter observability parity
   - Added explicit error logging when fallback path is used.
8. BigQuery plugin parity
   - Default `useBigQueryInsertAllSink = true`.
   - Safe callback now logs callback name + swallowed errors.
   - Event logging now tolerates formatter exceptions.
   - Added `content_parts` extraction for multimodal logging path.

## Tests and validation
- `dart analyze` on changed plugin/runtime files and tests: no errors (info-level only).
- Targeted tests:
  - `test/plugin_manager_test.dart`
  - `test/global_instruction_plugin_test.dart`
  - `test/bigquery_agent_analytics_plugin_parity_test.dart`
  - `test/runner_flow_test.dart`
  - `test/flow_processors_parity_test.dart`
- Result: `37 passed, 1 skipped, 0 failed`.
