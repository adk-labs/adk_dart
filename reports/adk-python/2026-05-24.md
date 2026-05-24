# ADK Python Daily Change Report

- Date (UTC): `2026-05-24`
- Source: `google/adk-python`
- Latest SHA: `7ad7994744de18f2394e4bcb961cd5c7a24afb4b`
- Previous SHA: `7ad7994744de18f2394e4bcb961cd5c7a24afb4b`

## Summary

- New commits: 0
- No new upstream Python commits were detected after the 2026-05-23 report.
- Dart runtime parity work was applied for already tracked Python changes: MCP graceful error handling/startup error observation, Gemini live transcription flush, grounding-only live response preservation, environment edit matching, telemetry user attribution, and tool-response error telemetry.

## Runtime-Relevant Changes Applied

- `src/google/adk/models/gemini_llm_connection.py` -> `lib/src/models/gemini_llm_connection.dart`
- `src/google/adk/flows/llm_flows/base_llm_flow.py` -> `lib/src/flows/llm_flows/base_llm_flow.dart`
- `src/google/adk/tools/environment/_tools.py` -> `lib/src/tools/environment/environment_toolset.dart`
- `src/google/adk/tools/mcp_tool/session_context.py` -> `lib/src/tools/mcp_tool/session_context.dart`
- `src/google/adk/tools/function_tool.py` -> `lib/src/tools/function_tool.dart`
- `src/google/adk/tools/base_tool.py` -> `lib/src/tools/base_tool.dart`
- `src/google/adk/telemetry/tracing.py` -> `lib/src/telemetry/tracing.dart`
- `src/google/adk/telemetry/_experimental_semconv.py` -> `lib/src/telemetry/_experimental_semconv.dart`

## Remaining Gaps

- Python v2 workflow/node runtime remains a separate design and porting effort.
- Python `adk web` CLI/server split and browser asset refresh require a separate dev-server/UI parity pass.
- Python sample tree relocation and `.agents/skills/*` documentation do not directly map to Dart runtime code and are tracked as documentation/sample gaps.
