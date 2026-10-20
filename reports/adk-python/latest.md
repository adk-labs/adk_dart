# ADK Python Daily Change Report

- Date (UTC): 2026-10-20
- Source: `google/adk-python`
- Latest SHA: `e02b2bff416602476cd94e8f9184a9fda1879444`
- Previous SHA: `ebbfb0ee5166424240156ab9056f2bf67f5af784`

## Summary

- New commits: 21

## Commits

- [e02b2bff](https://github.com/google/adk-python/commit/e02b2bff416602476cd94e8f9184a9fda1879444) fix: use a real CallToolResult in agent identity 2LO MCP tests (Liang Wu, 2026-10-20)
- [f1c23e30](https://github.com/google/adk-python/commit/f1c23e30882a0593b40c09ea373d03f664554bd4) fix: accept Gemini 3 and later in the CFC and example gates (George Weale, 2026-10-20)
- [662b0175](https://github.com/google/adk-python/commit/662b0175aa23605d4936c36ec60609ad8bbca09f) fix: record a nested state write only when its container converts to JSON unchanged (George Weale, 2026-10-20)
- [77a74f02](https://github.com/google/adk-python/commit/77a74f0206eaf8542e4db6243d4b9dc7965f4475) fix: copy events and search results in InMemoryMemoryService (Cherry, 2026-10-20)
- [6727f8f5](https://github.com/google/adk-python/commit/6727f8f5617509f88d2b3d4e5bf49c59d3b0e539) fix: route the turn after a paused single_turn sub-agent to its delegator (Somay-kousis, 2026-10-20)
- [8909689a](https://github.com/google/adk-python/commit/8909689ae46de5ecadd12cd8fccfdee6a32b67cc) docs: fix get_gcp_exporters docstring argument names (yetuge, 2026-10-20)
- [3b3de80f](https://github.com/google/adk-python/commit/3b3de80f1ab75f0adf210c1eab1e440cd61d8c7b) fix(workflow): preserve route and retry order during replay interception (Thomas Zettl, 2026-10-20)
- [d5c87a66](https://github.com/google/adk-python/commit/d5c87a66cff0333b8afb3bbb2fd64204251d23a8) feat(plugins): classify write-time 403 and 404 drops in BigQueryAgentAnalyticsPlugin (Haiyuan Cao, 2026-10-19)
- [365084db](https://github.com/google/adk-python/commit/365084db7b14e796f36ad2929f987e8d83874961) test(vmaas): add live integration tests for AgentEngineEnvironment (Google Team Member, 2026-10-19)
- [019b2b21](https://github.com/google/adk-python/commit/019b2b21f9b68a344efd6b92f4f7a40a7c6e273b) fix(vmaas): report sandbox timeouts and retry commands only when safe (Google Team Member, 2026-10-19)
- [1def14ba](https://github.com/google/adk-python/commit/1def14ba8efa662a5fa5d3b4c368ec8eecc9a2d6) fix(core): stop the unsafe local code executor waiting forever (George Weale, 2026-10-19)
- [486ef302](https://github.com/google/adk-python/commit/486ef302cf6cc620c13d0e2bb0e1d98d5d66cf02) fix: run a task delegation sent in the same turn as finish_task (Arjun Prabhulal, 2026-10-19)
- [43bab7db](https://github.com/google/adk-python/commit/43bab7db04b4418eec1b55e9eb0e73a72504b9d4) docs(live): fix run_live and CascadeLive snippets and document LiveRequest.state_delta (Shangjie Chen, 2026-10-19)
- [6e026995](https://github.com/google/adk-python/commit/6e02699531946a00637e58634c2ce9cabeb450b0) fix: clear strict mypy errors in model connectors and telemetry (George Weale, 2026-10-19)
- [12726f7a](https://github.com/google/adk-python/commit/12726f7a9775dfb46eddea044742efd89956ac1e) fix: support callables with positional-only arguments in FunctionTool (Moayad Alshehri, 2026-10-19)
- [b0e59521](https://github.com/google/adk-python/commit/b0e59521dbc9b15d7ccbf634b5f61dc6dc2d15ae) fix(workflow): run a resumed sub-agent again when control transfers back to it (Google Team Member, 2026-10-19)
- [da121d7b](https://github.com/google/adk-python/commit/da121d7bd8be75806b9f87a8323bac0677701169) fix: yield turn_complete and interrupted after flushing live audio (George Weale, 2026-10-19)
- [db432dba](https://github.com/google/adk-python/commit/db432dbae7c92df1c88b6d37d82a36c86998becb) fix: keep integers outside 64 bits exact in SqliteSessionService state (Somay-kousis, 2026-10-19)
- [626bd207](https://github.com/google/adk-python/commit/626bd20717100edf781a738c65c92e40b183d179) fix: recover the correct occurrence of reused compacted tool calls (LingYi, 2026-10-19)
- [13dde39b](https://github.com/google/adk-python/commit/13dde39b685aee292be9056f63a7ca24214950de) fix: give each retry of a dynamic function node fresh arguments (Arjun Prabhulal, 2026-10-19)
- [30726eaf](https://github.com/google/adk-python/commit/30726eaf0aab26d61474d96acb4cdd2beadbc083) fix: add SSRF protection to RestApiTool (Neelagiri65, 2026-10-19)

## Changed Files

- `M	.agents/skills/adk-architecture/references/interface-workflow.md`
- `M	contributing/samples/integrations/authn-adk-all-in-one/adk_agents/agent_openapi_tools/agent.py`
- `M	docs/guides/live/cascade_live/index.md`
- `M	docs/guides/live/live_request_queue/index.md`
- `M	docs/guides/runners/runner/live.md`
- `M	src/google/adk/agents/_agent_router.py`
- `M	src/google/adk/code_executors/unsafe_local_code_executor.py`
- `M	src/google/adk/examples/example_util.py`
- `M	src/google/adk/flows/llm_flows/context/_compaction.py`
- `M	src/google/adk/flows/llm_flows/context/_fencing.py`
- `M	src/google/adk/integrations/openai/_openai_llm.py`
- `M	src/google/adk/integrations/openai/_openai_responses_llm.py`
- `M	src/google/adk/integrations/vmaas/_agent_engine_environment.py`
- `M	src/google/adk/live/_live_llm_flow.py`
- `M	src/google/adk/memory/in_memory_memory_service.py`
- `M	src/google/adk/models/anthropic_llm.py`
- `M	src/google/adk/models/gemini_llm_connection.py`
- `M	src/google/adk/models/google_llm.py`
- `M	src/google/adk/models/interactions_utils.py`
- `M	src/google/adk/plugins/bigquery_agent_analytics_plugin.py`
- `M	src/google/adk/runners.py`
- `M	src/google/adk/sessions/sqlite_session_service.py`
- `M	src/google/adk/sessions/state.py`
- `M	src/google/adk/telemetry/_gcp_resource.py`
- `M	src/google/adk/telemetry/google_cloud.py`
- `M	src/google/adk/telemetry/tracing.py`
- `M	src/google/adk/tools/_url_validator.py`
- `M	src/google/adk/tools/agent_tool.py`
- `M	src/google/adk/tools/apihub_tool/apihub_toolset.py`
- `M	src/google/adk/tools/application_integration_tool/application_integration_toolset.py`
- `M	src/google/adk/tools/function_tool.py`
- `M	src/google/adk/tools/load_web_page.py`
- `M	src/google/adk/tools/openapi_tool/openapi_spec_parser/openapi_toolset.py`
- `M	src/google/adk/tools/openapi_tool/openapi_spec_parser/rest_api_tool.py`
- `M	src/google/adk/workflow/_dynamic_node_scheduler.py`
- `M	src/google/adk/workflow/_function_node.py`
- `M	src/google/adk/workflow/_llm_agent_wrapper.py`
- `M	src/google/adk/workflow/utils/_rehydration_utils.py`
- `M	src/google/adk/workflow/utils/_replay_interceptor.py`
- `M	src/google/adk/workflow/utils/_replay_manager.py`
- `M	tests/integration/integrations/agent_identity/test_2lo_flow.py`
- `M	tests/integration/integrations/agent_identity/test_agent_identity_2lo_flow.py`
- `A	tests/integration/integrations/vmaas/test_agent_engine_environment_live.py`
- `M	tests/unittests/agents/test_agent_router.py`
- `M	tests/unittests/agents/test_llm_agent_interruptions.py`
- `M	tests/unittests/code_executors/test_unsafe_local_code_executor.py`
- `M	tests/unittests/examples/test_example_util.py`
- `M	tests/unittests/flows/llm_flows/context/test_content_compaction.py`
- `M	tests/unittests/integrations/openai/test_openai_responses_llm.py`
- `M	tests/unittests/integrations/vmaas/test_agent_engine_environment.py`
- `M	tests/unittests/live/test_live_llm_flow.py`
- `M	tests/unittests/memory/test_in_memory_memory_service.py`
- `M	tests/unittests/models/test_interactions_utils.py`
- `M	tests/unittests/plugins/test_bigquery_agent_analytics_plugin.py`
- `M	tests/unittests/sessions/test_session_service.py`
- `M	tests/unittests/sessions/test_state.py`
- `M	tests/unittests/telemetry/test_gcp_resource.py`
- `M	tests/unittests/telemetry/test_spans.py`
- `M	tests/unittests/test_runners.py`
- `M	tests/unittests/tools/openapi_tool/openapi_spec_parser/test_rest_api_tool.py`
- `M	tests/unittests/tools/test_function_tool.py`
- `M	tests/unittests/workflow/test_agent_transfer.py`
- `M	tests/unittests/workflow/test_dynamic_node_scheduler.py`
- `M	tests/unittests/workflow/test_node_runner_failure.py`
- `M	tests/unittests/workflow/test_task_api_e2e.py`
- `M	tests/unittests/workflow/utils/test_replay_interceptor.py`
- `M	tests/unittests/workflow/utils/test_replay_manager.py`
