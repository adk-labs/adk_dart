# 2026-11-14 Upstream Parity Sync & Release (`2026.11.14`)

## Summary

Synced `adk_dart`, `packages/adk`, `packages/adk_mcp`, `packages/adk_litertlm`, and `packages/flutter_adk` against upstream `adk-python` (`df9f9d0452c02e2d461899f34acfb756e9612746..287c0b0e65899b0060efd5672c8f419c1119530d`, 15 commits across 44 `src/` files, bumping baseline `adkVersion` to `2.14.1`) and verified `adk-web` (`969cee92b7e249f4b66c3de1f2d354ab012fc0ce`, already up to date), updated `flutter_adk` evaluation and Google Maps tool UI parity, and released `2026.11.14`.

## Upstream Reference Heads

- `adk-python`: `287c0b0e65899b0060efd5672c8f419c1119530d`
- `adk-web`: `969cee92b7e249f4b66c3de1f2d354ab012fc0ce`

## Key Changes Ported

1. **Google Maps Platform Integration (`e76253fa`)**:
   - Added `lib/src/integrations/google_maps/` (`GoogleMapsToolset`, `GoogleMapsConfig`, `StreetViewResult`, `PropertyClassification`, `AddressType`, `get_street_view_image`, `validate_address`, `reverse_geocode`) with explicit API key, `MAPS_API_KEY`, and Secret Manager credential resolution, JPEG artifact saving, HTTPS/SSRF validation, and bounded LRU caching (`5371bb12f`).
2. **Live Background Function Calls & Remote A2A Workflow Output (`9a29cf42`)**:
   - Executed every live function call in its own background task in `runLive` (`launchFunctionCallsLive`, `mergeFunctionResponses`), yielding each finished `FunctionResponse` individually in completion order without blocking model audio/transcription/interruption streaming, isolating tool errors via `onToolErrorCallback`, cancelling running background tools on session restarts, draining non-streaming tools up to `10s` on normal exit, normalizing `null` long-running results, and yielding already-finished tool responses before rethrowing when the live connection fails (`e5dd820da`, `e237ec06c`, `1a0ddabf1`).
   - Skipped promoting failed remote A2A tasks (`TASK_STATE_FAILED` / `failed`) to `event.output` in `RemoteA2aAgent.promoteResponseToOutput` while still promoting completed tasks carrying an `errorCode` such as `MAX_TOKENS` (`f67cc356c`).
3. **Plugins, Nested `AgentTool` State Isolation & Telemetry (`15ce01e0`)**:
   - Added `InvocationContext.parentInvocationId` stamped by `AgentTool` (`includePlugins: true`), isolated nested `AgentTool` trace stacks and stamped `attributes.adk.{parent_session_id,parent_invocation_id}` in `BigQueryAgentAnalyticsPlugin`, hardened ASCII-escape credential sanitization, added `BigQueryLoggerConfig.responseTextKey`, and synced `eval_view_ctes_v1.sql` (`5ce1d0c15`).
   - Added `lib/src/utils/credential_names.dart` and masked credential material in telemetry serialization and `AutoTracingPlugin` (`b6952874a`).
   - Traced sub-agents by inherited `LlmAgent.canonicalModel` (`5112046cb`), stamped `GenerateContentSpan.endedAtMicros` for fallback inference duration (`8d857f47d`), used `{inference_call}` and `{tool_call}` semconv units (`56b25c619`), recorded the 7 `gen_ai.client.inference.*` token metrics in both schema v1 and v2 (`1de97607c`), and honored `RunConfig.telemetry` in `ModelConsultTool` advisor calls (`f9d948c58`).
4. **Multi-Run Evaluation Summaries, CLI Watcher Fix & `flutter_adk` UI (`d29ccc94`)**:
   - Added `MethodResult`, `MultiRunCaseSummary`, `EvalSetResult.multiRunCaseSummaries`, `EvaluateConfig.multiRunConfig`, `summarizeEvalCaseResults`, and `prettyPrintMultiRunSummaryTable` (`adk eval` default Pass Rate summary & `.evalset_result.json` persistence, `287c0b0e6`).
   - Guarded agents file watcher creation in `ApiServer` / `AdkWebServer` / `DevServer` behind `reloadAgents` / `setupObserver` (`12aab4aaa`).
   - Updated `AdkMultiRunEvalCard` and Google Maps tool recognition in `flutter_adk`.
