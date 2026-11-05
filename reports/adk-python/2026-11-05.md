# ADK Python Daily Change Report

- Date (UTC): 2026-11-05
- Source: `google/adk-python`
- Latest SHA: `32c202e819fb5867ec1aed15b07d2e66e0e5b36d`
- Previous SHA: `02db0ff256d9889b4a3a730bcaf5b63275b7ecc7`

## Summary

- New commits: 23

## Commits

- [32c202e8](https://github.com/google/adk-python/commit/32c202e819fb5867ec1aed15b07d2e66e0e5b36d) fix: send max_completion_tokens for Apigee reasoning models (samecho, 2026-11-05)
- [68ee0846](https://github.com/google/adk-python/commit/68ee084659fdb743d35ad4c4fb5ddcd28ea53999) docs: fix syntax errors and language tags in sample READMEs (Anil Pradhan, 2026-11-05)
- [17568220](https://github.com/google/adk-python/commit/175682204360faaa2cbbe5e6d99e090cc155608d) fix(workflow): isolate and preserve user_content for single-turn workflow nodes (Michael Rygiel, 2026-11-05)
- [907414b7](https://github.com/google/adk-python/commit/907414b7eb2debf5d7daa0432fc8f63e1692206e) fix(live): yield interrupted before saving the model's audio on a barge-in (Google Team Member, 2026-11-05)
- [640d2485](https://github.com/google/adk-python/commit/640d2485d6e90910c46d63ae340d84e5ed550fc6) fix: send Enum members in tool results as their values (George Weale, 2026-11-05)
- [94be06f6](https://github.com/google/adk-python/commit/94be06f6e25a909436a28cfad723f5215043b4d6) fix: record inference token metrics under google-genai instrumentor 0.7b2 (Google Team Member, 2026-11-05)
- [b4bf854d](https://github.com/google/adk-python/commit/b4bf854ddad631b1250e4ad639cb44a402ba0894) fix: capture app_details debug log on the google_adk logger in its test (Google Team Member, 2026-11-05)
- [e648b71b](https://github.com/google/adk-python/commit/e648b71beca74e210104fc9a0bcca28a7152b94c) fix: send structured output schemas on Apigee chat completions (samecho, 2026-11-05)
- [89ae4d35](https://github.com/google/adk-python/commit/89ae4d3537c2abbf072da3118408bce9450c6146) fix: keep Chinese and Japanese lines in load_web_page (Michael, 2026-11-05)
- [0192edd3](https://github.com/google/adk-python/commit/0192edd395986c6cc1a92ea9321be21ed32f0cfa) fix(plugins): close wrapped generators in AutoTracingPlugin (Google Team Member, 2026-11-05)
- [92b93c86](https://github.com/google/adk-python/commit/92b93c860b37e09408bfa8ac3b8c78871f2539b3) fix: end every Claude request on a user turn (ninglinLiu, 2026-11-04)
- [5e83dd5b](https://github.com/google/adk-python/commit/5e83dd5b2bd2d7bc80514efaa46f963052b27a70) feat(plugins): add eval session and turn query templates with filters (Haiyuan Cao, 2026-11-04)
- [54a6bbbf](https://github.com/google/adk-python/commit/54a6bbbfc59e247c6552555cffcdf2faf4810699) fix: keep a2a converters utils importable without the a2a extra (Haran Rajkumar, 2026-11-04)
- [6b2d4552](https://github.com/google/adk-python/commit/6b2d45523b06fd2e5a8ba5f52c2270f93d1607a4) fix: stop concurrent writes losing app: and user: state (Atul Joshi, 2026-11-04)
- [245f5d59](https://github.com/google/adk-python/commit/245f5d590a49783efe6700f7a8231908c23e0a18) fix: keep $defs of a recursive output_schema in OpenAI strict mode (Yasser-Ameur, 2026-11-04)
- [80bd3385](https://github.com/google/adk-python/commit/80bd338576a7cbab6477b01049052c89cbcd695f) fix: send media a tool returns to the Interactions API (Aditya Singh, 2026-11-04)
- [e4f6c3a9](https://github.com/google/adk-python/commit/e4f6c3a9c8fc8683a7493b62f0e8af5e04b396e4) fix: score each invocation against its own rubrics in rubric-based metrics (Yi Liu, 2026-11-04)
- [61f81433](https://github.com/google/adk-python/commit/61f814335bba37f0beeece48fe8b952576cbbac9) fix: emit no empty event from BuiltInCodeExecutor (Aditya Singh, 2026-11-04)
- [a702e3c0](https://github.com/google/adk-python/commit/a702e3c083c893794e78ac15d6dc044798905326) fix: enforce ExecuteBashTool resource limits that are set to 0 (Michael, 2026-11-04)
- [16898f30](https://github.com/google/adk-python/commit/16898f30c9a5c6b2ae1ecf099424afff8fd28e77) fix(plugins): mark truncated eval turns not ready (Haiyuan Cao, 2026-11-04)
- [e87ef73d](https://github.com/google/adk-python/commit/e87ef73d4dcc87f88a3af9a23115daade78192e2) fix: send gs:// file parts to Claude as inline base64 (danieldutu, 2026-11-04)
- [5e4f0e18](https://github.com/google/adk-python/commit/5e4f0e18cfe869a183901192f92c86d7574881b0) feat: support bounded parallel agent workers (Meher Gajula, 2026-11-04)
- [10b71623](https://github.com/google/adk-python/commit/10b716235500c12bb439fd10e57267da1e7d0dad) fix(plugins): answer failed tool calls in eval traces and skip HITL tools (Haiyuan Cao, 2026-11-04)

## Changed Files

- `M	contributing/samples/context_management/postgres_session_service/README.md`
- `M	contributing/samples/core/hello_world/README.md`
- `M	contributing/samples/hitl/request_input_tool/README.md`
- `M	contributing/samples/hitl/tool_confirmation/README.md`
- `M	contributing/samples/integrations/langchain_youtube_search_agent/README.md`
- `M	contributing/samples/multi_agent/single_turn_sub_agent/README.md`
- `M	contributing/samples/multi_agent/task_sub_agent/README.md`
- `M	docs/guides/workflow/parallel_worker/index.md`
- `M	src/google/adk/a2a/converters/utils.py`
- `M	src/google/adk/agents/llm_agent.py`
- `M	src/google/adk/evaluation/llm_as_judge.py`
- `M	src/google/adk/evaluation/rubric_based_evaluator.py`
- `M	src/google/adk/flows/llm_flows/context/_contents.py`
- `M	src/google/adk/flows/llm_flows/extensions/_code_execution.py`
- `M	src/google/adk/flows/llm_flows/tools/_caller.py`
- `M	src/google/adk/integrations/openai/_openai_llm.py`
- `M	src/google/adk/integrations/openai/_openai_responses_llm.py`
- `D	src/google/adk/integrations/openai/_openai_schema.py`
- `M	src/google/adk/integrations/redis/_redis_session_service.py`
- `M	src/google/adk/live/_live_llm_flow.py`
- `M	src/google/adk/models/anthropic_llm.py`
- `M	src/google/adk/models/apigee_llm.py`
- `M	src/google/adk/models/interactions_utils.py`
- `M	src/google/adk/models/lite_llm.py`
- `M	src/google/adk/plugins/__init__.py`
- `A	src/google/adk/plugins/_bigquery_agent_analytics_sql_utils.py`
- `M	src/google/adk/plugins/auto_tracing_helpers.py`
- `M	src/google/adk/plugins/bigquery_agent_analytics_plugin.py`
- `A	src/google/adk/plugins/bigquery_agent_analytics_sql/eval_session_query_v1.sql`
- `D	src/google/adk/plugins/bigquery_agent_analytics_sql/eval_session_view_v1.sql`
- `A	src/google/adk/plugins/bigquery_agent_analytics_sql/eval_turn_query_v1.sql`
- `D	src/google/adk/plugins/bigquery_agent_analytics_sql/eval_turn_view_v1.sql`
- `M	src/google/adk/plugins/bigquery_agent_analytics_sql/eval_view_ctes_v1.sql`
- `M	src/google/adk/sessions/database_session_service.py`
- `M	src/google/adk/telemetry/_genai_instrumentor.py`
- `M	src/google/adk/tools/bash_tool.py`
- `M	src/google/adk/tools/load_web_page.py`
- `M	src/google/adk/utils/_schema_utils.py`
- `M	src/google/adk/workflow/_llm_agent_wrapper.py`
- `M	src/google/adk/workflow/utils/_workflow_graph_utils.py`
- `M	tests/unittests/a2a/converters/test_utils.py`
- `M	tests/unittests/evaluation/test_app_details.py`
- `M	tests/unittests/evaluation/test_rubric_based_evaluator.py`
- `M	tests/unittests/flows/llm_flows/extensions/test_code_execution.py`
- `M	tests/unittests/flows/llm_flows/tools/test_caller.py`
- `M	tests/unittests/integrations/openai/test_openai_responses_llm.py`
- `M	tests/unittests/integrations/redis/test_redis_session_service.py`
- `M	tests/unittests/live/test_live_llm_flow.py`
- `M	tests/unittests/models/test_anthropic_llm.py`
- `M	tests/unittests/models/test_completions_http_client.py`
- `M	tests/unittests/models/test_interactions_utils.py`
- `M	tests/unittests/models/test_litellm.py`
- `M	tests/unittests/optimization/gepa_root_agent_optimizer_test.py`
- `M	tests/unittests/optimization/gepa_root_agent_prompt_optimizer_test.py`
- `M	tests/unittests/plugins/test_auto_tracing_helpers.py`
- `M	tests/unittests/plugins/test_bigquery_agent_analytics_plugin.py`
- `M	tests/unittests/plugins/test_bigquery_agent_analytics_sql_sync.py`
- `M	tests/unittests/sessions/test_session_service.py`
- `M	tests/unittests/telemetry/test_functional.py`
- `M	tests/unittests/test_optional_dependencies.py`
- `M	tests/unittests/tools/test_bash_tool.py`
- `M	tests/unittests/tools/test_load_web_page.py`
- `M	tests/unittests/workflow/test_llm_agent_as_node.py`
- `M	tests/unittests/workflow/test_workflow_parallel_worker.py`
