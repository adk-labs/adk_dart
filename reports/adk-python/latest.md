# ADK Python Daily Change Report

- Date (UTC): 2026-11-09
- Source: `google/adk-python`
- Latest SHA: `b989d684945f8d16baf3d7a64cb784cdc9b58bd4`
- Previous SHA: `1cb926d5b8d702261ec82a26d3f1c4296e0db7d7`

## Summary

- New commits: 18

## Commits

- [b989d684](https://github.com/google/adk-python/commit/b989d684945f8d16baf3d7a64cb784cdc9b58bd4) fix: keep a text answer as text when the input request asks for a string (Arjun Prabhulal, 2026-11-09)
- [f1b1f9d9](https://github.com/google/adk-python/commit/f1b1f9d9606c61ca23dd09c4ecd5610167a2b0da) fix(eval): keep the session details of every eval case in its result (Yi Liu, 2026-11-09)
- [6fdc9537](https://github.com/google/adk-python/commit/6fdc9537a765fa5d10dfc788429f3496f473b40d) fix: revert the change about giving a cloned LlmAgent tools for its own sub-agents (Shangjie Chen, 2026-11-09)
- [04ba4120](https://github.com/google/adk-python/commit/04ba412094d4d5b01aea4ffb25690068311a8ad6) feat(evaluation): add configurable tool parameter match metric (Yi Liu, 2026-11-09)
- [1bd22e34](https://github.com/google/adk-python/commit/1bd22e34d415cee15dca5d7b717c337f3dc604f7) feat(environment): pass the calling context to BaseEnvironment methods (Liang Wu, 2026-11-09)
- [7941f8d5](https://github.com/google/adk-python/commit/7941f8d5b69cc66491e73eb2c19c3d93068d2019) fix: upgrade watchdog for Python 3.14 macOS wheels (Peter Lithammer, 2026-11-09)
- [ba43b4f0](https://github.com/google/adk-python/commit/ba43b4f0a0cf48ad86620b94ff467c7f79e379d5) fix: name the calling node in the rerun_on_resume error (Mangesh Raut, 2026-11-09)
- [88b3afe7](https://github.com/google/adk-python/commit/88b3afe70c9b7b4edb95532998b2efdfad6e2a00) fix(tracing): turn off FastAPI's native tracing on Agent Engine (Max Ind, 2026-11-09)
- [112491db](https://github.com/google/adk-python/commit/112491db84bc4de3d22c13d5925efffdb8ea1bb8) perf: reuse RAG API clients per event loop, cutting memory search 6x (George Weale, 2026-11-09)
- [319b5a70](https://github.com/google/adk-python/commit/319b5a70e9ce500490d8d1a81c38392a05c73ed5) fix: respect display_name from .agent_engine_config.json (tosuri13, 2026-11-09)
- [b979abe5](https://github.com/google/adk-python/commit/b979abe5784a344185bacd441ed74b3ba1d95d32) feat: let toolsets opt out of caching their tools per invocation (Jason Zhang, 2026-11-09)
- [f0086e3f](https://github.com/google/adk-python/commit/f0086e3f45eb6ddf06c695f7509fd74fdeb1bbf8) fix: type agent loaders as returning any workflow node (George Weale, 2026-11-09)
- [e1e231cb](https://github.com/google/adk-python/commit/e1e231cb34c82783990ff29419e279ae354b82be) fix: leave paused long-running calls open when the run task is cancelled (George Weale, 2026-11-09)
- [b41fc578](https://github.com/google/adk-python/commit/b41fc578a5db964701fce5cab0f9d26c5d6eaaf0) fix: give a cloned LlmAgent tools for its own sub-agents (hyeonsang010716, 2026-11-09)
- [e9f9790f](https://github.com/google/adk-python/commit/e9f9790f94585219061b73156edc890a44b2425b) fix: split mixed-script search queries in InMemoryMemoryService (Atul Joshi, 2026-11-09)
- [ddb812e1](https://github.com/google/adk-python/commit/ddb812e1874a835f0a94eb12408e3801c0be4451) fix: type ComputerUseToolset's pickled state (George Weale, 2026-11-09)
- [9651df04](https://github.com/google/adk-python/commit/9651df04d6680720a061b37f45561ecd0417279b) fix: run service account token exchange off the event loop (George Weale, 2026-11-09)
- [67b217d0](https://github.com/google/adk-python/commit/67b217d009cbcdd5827f035e001620dbe08e839b) fix: run synchronous metric evaluators off the event loop (Rafael Ladeira, 2026-11-08)

## Changed Files

- `M	constraints-3.11.txt`
- `M	constraints-3.12.txt`
- `M	constraints-3.13.txt`
- `M	constraints-3.14.txt`
- `M	constraints-3.15.txt`
- `M	docs/guides/environment/base_environment/index.md`
- `M	docs/guides/evaluation/eval_config/index.md`
- `M	docs/guides/evaluation/evaluator/index.md`
- `M	docs/guides/runners/runner/abort.md`
- `M	docs/guides/tools/base_toolset/index.md`
- `M	pyproject.toml`
- `M	scripts/update_constraints.sh`
- `M	src/google/adk/auth/credential_manager.py`
- `M	src/google/adk/cli/agent_test_runner.py`
- `M	src/google/adk/cli/api_server.py`
- `M	src/google/adk/cli/cli.py`
- `M	src/google/adk/cli/cli_deploy.py`
- `M	src/google/adk/cli/dev_server.py`
- `M	src/google/adk/cli/utils/_nested_agent_loader.py`
- `M	src/google/adk/cli/utils/agent_loader.py`
- `M	src/google/adk/cli/utils/base_agent_loader.py`
- `M	src/google/adk/environment/_base_environment.py`
- `M	src/google/adk/environment/_local_environment.py`
- `A	src/google/adk/evaluation/_tool_parameter_match_evaluator.py`
- `M	src/google/adk/evaluation/custom_metric_evaluator.py`
- `M	src/google/adk/evaluation/eval_metrics.py`
- `M	src/google/adk/evaluation/evaluation_generator.py`
- `M	src/google/adk/evaluation/evaluator.py`
- `M	src/google/adk/evaluation/local_eval_service.py`
- `M	src/google/adk/evaluation/metric_evaluator_registry.py`
- `M	src/google/adk/evaluation/metric_info_providers.py`
- `M	src/google/adk/events/_abort_events.py`
- `M	src/google/adk/integrations/daytona/_daytona_environment.py`
- `M	src/google/adk/integrations/e2b/_e2b_environment.py`
- `M	src/google/adk/integrations/opensandbox/_opensandbox_environment.py`
- `M	src/google/adk/integrations/vmaas/_agent_engine_environment.py`
- `M	src/google/adk/memory/in_memory_memory_service.py`
- `M	src/google/adk/memory/vertex_ai_rag_memory_service.py`
- `M	src/google/adk/runners.py`
- `M	src/google/adk/tools/base_toolset.py`
- `M	src/google/adk/tools/computer_use/computer_use_toolset.py`
- `M	src/google/adk/tools/environment/_edit_file_tool.py`
- `M	src/google/adk/tools/environment/_environment_toolset.py`
- `M	src/google/adk/tools/environment/_execute_tool.py`
- `M	src/google/adk/tools/environment/_read_file_tool.py`
- `M	src/google/adk/tools/environment/_write_file_tool.py`
- `M	src/google/adk/tools/openapi_tool/auth/credential_exchangers/base_credential_exchanger.py`
- `M	src/google/adk/tools/openapi_tool/openapi_spec_parser/tool_auth_handler.py`
- `M	src/google/adk/tools/retrieval/vertex_ai_rag_retrieval.py`
- `M	src/google/adk/tools/skill_toolset.py`
- `M	src/google/adk/utils/_runner_utils.py`
- `M	src/google/adk/workflow/_dynamic_node_scheduler.py`
- `M	src/google/adk/workflow/utils/_rehydration_utils.py`
- `M	tests/unittests/auth/test_credential_manager.py`
- `M	tests/unittests/cli/test_fast_api.py`
- `M	tests/unittests/cli/utils/test_cli.py`
- `M	tests/unittests/cli/utils/test_cli_deploy.py`
- `A	tests/unittests/environment/test_base_environment.py`
- `M	tests/unittests/evaluation/test_custom_metric_evaluator.py`
- `M	tests/unittests/evaluation/test_local_eval_service.py`
- `M	tests/unittests/evaluation/test_metric_evaluator_registry.py`
- `A	tests/unittests/evaluation/test_tool_parameter_match_evaluator.py`
- `M	tests/unittests/memory/test_in_memory_memory_service.py`
- `M	tests/unittests/memory/test_vertex_ai_rag_memory_service.py`
- `M	tests/unittests/test_runners.py`
- `M	tests/unittests/tools/environment/test_read_file_tool.py`
- `M	tests/unittests/tools/openapi_tool/openapi_spec_parser/test_tool_auth_handler.py`
- `M	tests/unittests/tools/retrieval/test_vertex_ai_rag_retrieval.py`
- `M	tests/unittests/tools/test_base_toolset.py`
- `M	tests/unittests/tools/test_environment_toolset.py`
- `M	tests/unittests/tools/test_skill_toolset.py`
- `M	tests/unittests/workflow/test_dynamic_node_executor.py`
- `M	tests/unittests/workflow/test_dynamic_node_scheduler.py`
- `M	tests/unittests/workflow/test_workflow_hitl.py`
