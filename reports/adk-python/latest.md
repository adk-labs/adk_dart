# ADK Python Daily Change Report

- Date (UTC): 2026-11-12
- Source: `google/adk-python`
- Latest SHA: `e5dd820da49433c73be1b1296c790f17ec3defa7`
- Previous SHA: `59b0dd63c32cc5dbf8475f1e0e555770aabaa6f0`

## Summary

- New commits: 6

## Commits

- [e5dd820d](https://github.com/google/adk-python/commit/e5dd820da49433c73be1b1296c790f17ec3defa7) feat(live): run every live function call in a background task (Jason Zhang, 2026-11-12)
- [f9d948c5](https://github.com/google/adk-python/commit/f9d948c58aa84b579355eeb10d9dc28f4f21d45c) feat(telemetry): use the run's telemetry config for model_consult advisor metrics (Google Team Member, 2026-11-12)
- [5371bb12](https://github.com/google/adk-python/commit/5371bb12fdb58303ed956912c145972e469543b4) feat(integrations): add Google Maps Platform integration (Shelby James, 2026-11-12)
- [df9f9d04](https://github.com/google/adk-python/commit/df9f9d0452c02e2d461899f34acfb756e9612746) feat(artifacts): add write, delete, and version metadata support to FsspecArtifactService (Google Team Member, 2026-11-12)
- [9620b429](https://github.com/google/adk-python/commit/9620b42965305294dba886ff38757dae3478c401) feat(live): add client label telemetry for CascadeLive reasoning turns (Google Team Member, 2026-11-11)
- [389f80a0](https://github.com/google/adk-python/commit/389f80a0e6b7c1fa4cc680018142e8aeef49b13d) feat: add samples for context filter, Model Armor and BigQuery plugins (Vishal Bulbule, 2026-11-11)

## Changed Files

- `A	contributing/samples/integrations/google_maps_photo_audit/README.md`
- `A	contributing/samples/integrations/google_maps_photo_audit/__init__.py`
- `A	contributing/samples/integrations/google_maps_photo_audit/agent.py`
- `M	contributing/samples/live/non_blocking_tool_agent/README.md`
- `A	contributing/samples/plugins/plugin_bigquery_agent_analytics/README.md`
- `A	contributing/samples/plugins/plugin_bigquery_agent_analytics/__init__.py`
- `A	contributing/samples/plugins/plugin_bigquery_agent_analytics/main.py`
- `A	contributing/samples/plugins/plugin_context_filter/README.md`
- `A	contributing/samples/plugins/plugin_context_filter/__init__.py`
- `A	contributing/samples/plugins/plugin_context_filter/main.py`
- `A	contributing/samples/plugins/plugin_model_armor/README.md`
- `A	contributing/samples/plugins/plugin_model_armor/__init__.py`
- `A	contributing/samples/plugins/plugin_model_armor/main.py`
- `M	docs/guides/README.md`
- `A	docs/guides/integrations/google_maps/index.md`
- `M	docs/guides/live/tools/index.md`
- `M	docs/guides/runners/runner/live.md`
- `M	pyproject.toml`
- `M	src/google/adk/agents/invocation_context.py`
- `M	src/google/adk/evaluation/evaluation_generator.py`
- `M	src/google/adk/flows/llm_flows/base_llm_flow.py`
- `M	src/google/adk/flows/llm_flows/tools/_agent_tools.py`
- `M	src/google/adk/flows/llm_flows/tools/_batch_executor.py`
- `M	src/google/adk/flows/llm_flows/tools/_functions.py`
- `M	src/google/adk/flows/llm_flows/tools/_live_caller.py`
- `M	src/google/adk/integrations/fsspec/__init__.py`
- `M	src/google/adk/integrations/fsspec/_fsspec_artifact_service.py`
- `A	src/google/adk/integrations/google_maps/README.md`
- `A	src/google/adk/integrations/google_maps/__init__.py`
- `A	src/google/adk/integrations/google_maps/_config.py`
- `A	src/google/adk/integrations/google_maps/_google_maps_toolset.py`
- `A	src/google/adk/integrations/google_maps/_models.py`
- `A	src/google/adk/integrations/google_maps/_services.py`
- `A	src/google/adk/integrations/google_maps/_tools.py`
- `M	src/google/adk/live/_active_background_tool.py`
- `M	src/google/adk/live/_cascade_live_connection.py`
- `M	src/google/adk/live/_flow_utils.py`
- `M	src/google/adk/live/_live_llm_flow.py`
- `M	src/google/adk/tools/base_tool.py`
- `M	src/google/adk/tools/function_tool.py`
- `M	src/google/adk/tools/model_consult/_advisor.py`
- `M	src/google/adk/tools/model_consult/_model_consult_tool.py`
- `M	src/google/adk/utils/_client_labels_utils.py`
- `M	tests/unittests/artifacts/test_artifact_service.py`
- `M	tests/unittests/flows/llm_flows/test_base_llm_flow.py`
- `M	tests/unittests/flows/llm_flows/tools/test_batch_executor.py`
- `M	tests/unittests/flows/llm_flows/tools/test_functions_parallel_error.py`
- `M	tests/unittests/flows/llm_flows/tools/test_functions_simple.py`
- `M	tests/unittests/flows/llm_flows/tools/test_live_caller.py`
- `M	tests/unittests/integrations/fsspec/test_fsspec_artifact_service.py`
- `A	tests/unittests/integrations/google_maps/__init__.py`
- `A	tests/unittests/integrations/google_maps/test_google_maps.py`
- `M	tests/unittests/live/test_cascade_live_connection.py`
- `M	tests/unittests/live/test_cascade_live_connection_barge_in.py`
- `M	tests/unittests/live/test_flow_utils.py`
- `M	tests/unittests/live/test_live_llm_flow.py`
- `M	tests/unittests/streaming/test_live_tool_shutdown.py`
- `M	tests/unittests/streaming/test_streaming.py`
- `M	tests/unittests/test_import_loading.py`
- `M	tests/unittests/tools/model_consult/test_advisor.py`
- `M	tests/unittests/tools/model_consult/test_model_consult_tool.py`
- `M	tests/unittests/utils/test_client_labels_utils.py`
