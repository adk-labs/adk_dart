# ADK Python Daily Change Report

- Date (UTC): 2026-10-26
- Source: `google/adk-python`
- Latest SHA: `cec52fc005a2c76963feb0a424647ca9576ebb2d`
- Previous SHA: `bf6739723c1b8b03bff8bb1e6ffada4d88098fcf`

## Summary

- New commits: 7

## Commits

- [cec52fc0](https://github.com/google/adk-python/commit/cec52fc005a2c76963feb0a424647ca9576ebb2d) fix: copy initial state in InMemorySessionService.create_session (xxwtiancai, 2026-10-26)
- [a96fc11b](https://github.com/google/adk-python/commit/a96fc11b58a92187ad6cdaba0059d6999964fbe8) fix: set error.type on spans that end in an error (Ankit Kumar, 2026-10-26)
- [3cd87427](https://github.com/google/adk-python/commit/3cd87427ac9c016b0cf335459a90c9902b0737d9) feat(live): save image frames when save_live_blob is set (Google Team Member, 2026-10-26)
- [58497627](https://github.com/google/adk-python/commit/5849762718871e206b7745f0318f8399a5dd5f52) fix(bigquery): improve error messages when write_mode is BLOCKED (Google Team Member, 2026-10-26)
- [4496bef7](https://github.com/google/adk-python/commit/4496bef701661b48221df56f75a89ff70449bcdc) fix: export all shipped plugins from google.adk.plugins (Vishal Bulbule, 2026-10-26)
- [3b227d6e](https://github.com/google/adk-python/commit/3b227d6ec82490dae6473f681dcc825b1ac31679) fix!: close malformed live WebSockets instead of wedging them (George Weale, 2026-10-26)
- [960cd5dd](https://github.com/google/adk-python/commit/960cd5ddfff135c39cf8dbe185f0f08a309c927c) fix: align gen_ai.choice system name with request model for LiteLLM (DDT, 2026-10-26)

## Changed Files

- `M	docs/guides/runners/runner/live.md`
- `M	src/google/adk/agents/invocation_context.py`
- `M	src/google/adk/cli/api_server.py`
- `M	src/google/adk/flows/llm_flows/core/_model_call.py`
- `M	src/google/adk/integrations/bigquery/query_tool.py`
- `M	src/google/adk/live/_flow_utils.py`
- `M	src/google/adk/live/_realtime_cache_manager.py`
- `M	src/google/adk/plugins/__init__.py`
- `M	src/google/adk/sessions/in_memory_session_service.py`
- `M	src/google/adk/telemetry/_instrumentation.py`
- `M	src/google/adk/telemetry/node_tracing.py`
- `M	src/google/adk/telemetry/tracing.py`
- `M	tests/unittests/cli/test_adk_web_server_run_live.py`
- `M	tests/unittests/integrations/bigquery/test_bigquery_query_tool.py`
- `M	tests/unittests/live/test_flow_utils.py`
- `M	tests/unittests/live/test_live_llm_flow.py`
- `M	tests/unittests/live/test_realtime_cache_manager.py`
- `A	tests/unittests/plugins/test_plugins_package.py`
- `M	tests/unittests/sessions/test_session_service.py`
- `M	tests/unittests/telemetry/functional/scenarios/telemetry_setup.py`
- `M	tests/unittests/telemetry/functional_divergences.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/inference-error-resource-exhausted-schema-v1.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/inference-error-resource-exhausted-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/inference-error-valueerror-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/inference-error-valueerror-span-and-event-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/tool-error-valueerror-schema-v2.json`
- `M	tests/unittests/telemetry/functional_goldens/agent/tool-error-valueerror-span-only-schema-v2.json`
- `M	tests/unittests/telemetry/test_semconv_conformance.py`
- `M	tests/unittests/telemetry/test_spans.py`
