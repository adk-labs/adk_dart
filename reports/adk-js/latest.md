# ADK JS Daily Change Report

- Date (UTC): 2026-11-14
- Source: `google/adk-js`
- Latest SHA: `a662b30976d68625a7348f3139bb41806aad7818`
- Previous SHA: `5389c26dfdc8bda1f2866410fa2cc9217a041e03`

## Summary

- New commits: 4

## Commits

- [a662b30](https://github.com/google/adk-js/commit/a662b30976d68625a7348f3139bb41806aad7818) feat(cli): reload only the changed agent with --reload_agents (#1322) (adk-foundry-bot, 2026-11-13)
- [4776b47](https://github.com/google/adk-js/commit/4776b4728744b6d70a70c8bef5565ce3b3074e3c) feat(a2a): add a request timeout and a card resolution error to RemoteA2AAgent (#1323) (adk-foundry-bot, 2026-11-13)
- [1ce9cfa](https://github.com/google/adk-js/commit/1ce9cfa11dff999a96002ce6968be81d18e85b8f) feat(a2a): add auth-required task state, runner caching and request logs (#1320) (adk-foundry-bot, 2026-11-13)
- [70612f2](https://github.com/google/adk-js/commit/70612f2f0c56988ac8c35cfecd5226a486e75cfe) fix(agents): give each streamed model event its own timestamp (#1319) (adk-foundry-bot, 2026-11-13)

## Changed Files

- `M	core/src/a2a/a2a_event.ts`
- `M	core/src/a2a/a2a_remote_agent.ts`
- `M	core/src/a2a/a2a_remote_agent_run_processor.ts`
- `M	core/src/a2a/a2a_remote_agent_utils.ts`
- `M	core/src/a2a/agent_card.ts`
- `M	core/src/a2a/agent_executor.ts`
- `M	core/src/a2a/event_converter_utils.ts`
- `M	core/src/a2a/event_processor_utils.ts`
- `M	core/src/a2a/index.ts`
- `A	core/src/a2a/log_utils.ts`
- `M	core/src/a2a/metadata_converter_utils.ts`
- `M	core/src/agents/llm_agent.ts`
- `M	core/src/sessions/in_memory_session_service.ts`
- `A	core/src/utils/fetch_utils.ts`
- `M	core/test/a2a/a2a_event_test.ts`
- `M	core/test/a2a/a2a_remote_agent_run_processor_test.ts`
- `A	core/test/a2a/a2a_remote_agent_test.ts`
- `M	core/test/a2a/agent_card_test.ts`
- `M	core/test/a2a/agent_executor_test.ts`
- `M	core/test/a2a/event_converter_utils_test.ts`
- `M	core/test/a2a/event_processor_utils_test.ts`
- `A	core/test/a2a/log_utils_test.ts`
- `M	core/test/a2a/remote_agent_test.ts`
- `M	core/test/a2a/remote_agent_utils_test.ts`
- `M	core/test/a2a/request_metadata_test.ts`
- `M	core/test/agents/base_agent_test.ts`
- `M	core/test/agents/llm_agent_test.ts`
- `M	core/test/agents/run_config_test.ts`
- `M	core/test/runner/run_live_test.ts`
- `M	core/test/sessions/database_session_service_test.ts`
- `M	core/test/sessions/in_memory_session_service_test.ts`
- `M	core/test/sessions/vertex_ai_session_service_test.ts`
- `M	core/test/tools/function_tool_test.ts`
- `M	core/test/tools/google_search_tool_test.ts`
- `M	core/test/tools/mcp/mcp_tool_test.ts`
- `A	core/test/utils/fetch_utils_test.ts`
- `M	dev/src/server/adk_api_server.ts`
- `M	dev/src/utils/agent_loader.ts`
- `M	dev/test/cli/cli_test.ts`
- `M	dev/test/server/adk_api_server_test.ts`
- `M	dev/test/utils/agent_loader_test.ts`
- `M	docs/guides/README.md`
- `M	docs/guides/a2a/index.md`
- `M	docs/guides/cli/index.md`
- `M	samples/cli/README.md`
