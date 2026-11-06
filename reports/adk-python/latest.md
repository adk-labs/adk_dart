# ADK Python Daily Change Report

- Date (UTC): 2026-11-06
- Source: `google/adk-python`
- Latest SHA: `10711d0532373f526a4438c8c0bcb93c4e81419c`
- Previous SHA: `32c202e819fb5867ec1aed15b07d2e66e0e5b36d`

## Summary

- New commits: 18

## Commits

- [10711d05](https://github.com/google/adk-python/commit/10711d0532373f526a4438c8c0bcb93c4e81419c) fix(mcp): retry a tool call once after the server drops the session (gioboa, 2026-11-06)
- [1fa00445](https://github.com/google/adk-python/commit/1fa00445f82409ad314df95808b28658a1ae0259) fix: preserve line endings in FileArtifactService text artifacts (emme1t, 2026-11-06)
- [58d1ebe3](https://github.com/google/adk-python/commit/58d1ebe32baade2d23477ecd9332ad6b98b1266b) fix: let MCP request headers replace static headers in any case (Arjun Prabhulal, 2026-11-06)
- [72663e5f](https://github.com/google/adk-python/commit/72663e5f036f90f7ff707e6e761eec98ddacb99a) fix: honor subclass validation aliases in Event and LlmAgent kwargs (He Yunhui, 2026-11-06)
- [982f6083](https://github.com/google/adk-python/commit/982f6083ce05420f92cdc7426d9c94de706a7684) fix: require confirmation before large reimbursements in hitl samples (Hanzhi, 2026-11-06)
- [946ca772](https://github.com/google/adk-python/commit/946ca77224d5b3e1bf7c5a1dd0a39e9b17c3e655) fix: preserve empty Anthropic thinking blocks (Haoyin Deng, 2026-11-06)
- [75fc8531](https://github.com/google/adk-python/commit/75fc85319f93abc54baf0ebe5b5fb7f71e483225) fix(workflow): key a resumed sub-agent's run by the path its events carry (Google Team Member, 2026-11-05)
- [90d352bd](https://github.com/google/adk-python/commit/90d352bdf1d4796c633bfa9850bd4bd2a2fd0504) fix: accept AgentTool input_schema args that use aliases (techi101, 2026-11-05)
- [537774f3](https://github.com/google/adk-python/commit/537774f300de610fd579015e05551026c38b17e4) chore: add tracking headers support to session and memory bank API clients (Yeesian Ng CA, 2026-11-05)
- [d61f4281](https://github.com/google/adk-python/commit/d61f4281d0af7e5047e1032018c9e7a41643e89e) fix: stop returning uncaught exception text to remote A2A peers and trigger callers (Yuhan Gao, 2026-11-05)
- [656696c4](https://github.com/google/adk-python/commit/656696c4d257b98e0d0c477f51fc96d4c0f9b1e0) fix: honor parallelism_limit in simulator and hallucination evals (Rafael Ladeira, 2026-11-05)
- [278fe051](https://github.com/google/adk-python/commit/278fe05134e83d96e9881dafc65382152e40d217) docs(plugins): add a unit guide for the eval query builders (Haiyuan Cao, 2026-11-05)
- [d09599e4](https://github.com/google/adk-python/commit/d09599e480f5d4165cacc11e5de63f2c70766f11) fix: raise the SqliteSessionService busy timeout to 30 seconds (George Weale, 2026-11-05)
- [d103e364](https://github.com/google/adk-python/commit/d103e364a480b07209682cf764c9711323a1417a) fix: deduplicate SlackRunner execution on thread mentions (George Weale, 2026-11-05)
- [5c7a8297](https://github.com/google/adk-python/commit/5c7a8297ef987672c37a6083ad31af99b8e2b66a) feat(eval): add pass@k and pass^k as multi-run cross-run criteria (Google Team Member, 2026-11-05)
- [a0339b77](https://github.com/google/adk-python/commit/a0339b776d27d44f252c18cf7e93d1b32f10323a) fix(sessions): isolate stored events and state deltas in append_event (Nathan Eng, 2026-11-05)
- [b33b43e5](https://github.com/google/adk-python/commit/b33b43e5b5388b9454c71f440eb885901075f43a) fix: use standard tool role for Gemma 4 on Vertex AI (Rafael Ladeira, 2026-11-05)
- [6507ad8d](https://github.com/google/adk-python/commit/6507ad8da73fb3d9a72cb8edd733b95c52c0ed27) fix(cli): return a fixed detail string when saving an artifact fails (George Weale, 2026-11-05)

## Changed Files

- `M	contributing/samples/hitl/human_in_loop/README.md`
- `M	contributing/samples/hitl/human_in_loop/agent.py`
- `M	contributing/samples/hitl/human_in_loop/main.py`
- `M	contributing/samples/hitl/human_in_loop/tests/reimburse_dinner.json`
- `M	contributing/samples/hitl/tool_human_in_the_loop_config/root_agent.yaml`
- `M	contributing/samples/hitl/tool_human_in_the_loop_config/tools.py`
- `M	docs/guides/README.md`
- `M	docs/guides/evaluation/eval_config/index.md`
- `A	docs/guides/plugins/bigquery_agent_analytics_eval_sql/index.md`
- `M	src/google/adk/a2a/executor/a2a_agent_executor.py`
- `M	src/google/adk/a2a/executor/a2a_agent_executor_impl.py`
- `M	src/google/adk/agents/llm_agent.py`
- `M	src/google/adk/artifacts/file_artifact_service.py`
- `M	src/google/adk/cli/api_server.py`
- `M	src/google/adk/cli/cli_tools_click.py`
- `M	src/google/adk/cli/trigger_routes.py`
- `M	src/google/adk/evaluation/_eval_case_result_multi_run_aggregator.py`
- `M	src/google/adk/evaluation/_multi_run_aggregation_methods.py`
- `M	src/google/adk/evaluation/eval_config.py`
- `M	src/google/adk/evaluation/hallucinations_v1.py`
- `M	src/google/adk/evaluation/llm_as_judge_utils.py`
- `M	src/google/adk/evaluation/simulation/per_turn_user_simulator_quality_v1.py`
- `M	src/google/adk/events/event.py`
- `M	src/google/adk/integrations/slack/slack_runner.py`
- `M	src/google/adk/memory/vertex_ai_memory_bank_service.py`
- `M	src/google/adk/models/anthropic_llm.py`
- `M	src/google/adk/models/lite_llm.py`
- `M	src/google/adk/plugins/__init__.py`
- `R089	src/google/adk/plugins/_bigquery_agent_analytics_sql_utils.py	src/google/adk/plugins/_bigquery_agent_analytics_eval_sql.py`
- `M	src/google/adk/plugins/bigquery_agent_analytics_plugin.py`
- `M	src/google/adk/plugins/bigquery_agent_analytics_sql/eval_turn_query_v1.sql`
- `M	src/google/adk/sessions/in_memory_session_service.py`
- `M	src/google/adk/sessions/sqlite_session_service.py`
- `M	src/google/adk/sessions/vertex_ai_session_service.py`
- `M	src/google/adk/tools/agent_tool.py`
- `M	src/google/adk/tools/mcp_tool/mcp_session_manager.py`
- `M	src/google/adk/tools/mcp_tool/mcp_tool.py`
- `A	src/google/adk/utils/_error_reporting.py`
- `M	src/google/adk/utils/_google_client_headers.py`
- `M	src/google/adk/utils/_schema_utils.py`
- `M	src/google/adk/workflow/_dynamic_node_scheduler.py`
- `M	tests/unittests/_invariants.py`
- `M	tests/unittests/a2a/executor/test_a2a_agent_executor.py`
- `M	tests/unittests/a2a/executor/test_a2a_agent_executor_impl.py`
- `M	tests/unittests/agents/test_llm_agent_error_messages.py`
- `M	tests/unittests/artifacts/test_artifact_service.py`
- `M	tests/unittests/cli/test_fast_api.py`
- `M	tests/unittests/cli/test_trigger_routes.py`
- `M	tests/unittests/cli/utils/test_cli_tools_click.py`
- `M	tests/unittests/evaluation/simulation/test_per_turn_user_simulation_quality_v1.py`
- `M	tests/unittests/evaluation/test_eval_case_result_multi_run_aggregator.py`
- `M	tests/unittests/evaluation/test_eval_config.py`
- `M	tests/unittests/evaluation/test_hallucinations_v1.py`
- `M	tests/unittests/evaluation/test_multi_run_aggregation_methods.py`
- `M	tests/unittests/events/test_event.py`
- `M	tests/unittests/flows/llm_flows/tools/test_functions_long_running.py`
- `M	tests/unittests/integrations/slack/test_slack_runner.py`
- `M	tests/unittests/memory/test_vertex_ai_memory_bank_service.py`
- `M	tests/unittests/models/test_anthropic_llm.py`
- `M	tests/unittests/models/test_lite_llm_gemma_tool_role.py`
- `M	tests/unittests/plugins/test_bigquery_agent_analytics_plugin.py`
- `M	tests/unittests/plugins/test_bigquery_agent_analytics_sql_sync.py`
- `M	tests/unittests/sessions/test_session_service.py`
- `M	tests/unittests/sessions/test_vertex_ai_session_service.py`
- `M	tests/unittests/test_invariants.py`
- `M	tests/unittests/test_optional_dependencies.py`
- `M	tests/unittests/test_samples.py`
- `M	tests/unittests/tools/mcp_tool/test_mcp_session_manager.py`
- `M	tests/unittests/tools/mcp_tool/test_mcp_tool.py`
- `M	tests/unittests/tools/test_agent_tool.py`
- `A	tests/unittests/utils/test_error_reporting.py`
- `M	tests/unittests/utils/test_google_client_headers.py`
- `M	tests/unittests/utils/test_schema_utils.py`
- `M	tests/unittests/workflow/test_agent_transfer.py`
- `M	tests/unittests/workflow/test_llm_agent_as_node.py`
- `M	tests/unittests/workflow/test_workflow.py`
