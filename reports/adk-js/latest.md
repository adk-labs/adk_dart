# ADK JS Daily Change Report

- Date (UTC): 2026-11-17
- Source: `google/adk-js`
- Latest SHA: `0fcab5503afa44012207b995864e59ff9012653d`
- Previous SHA: `e4879f8632ba3d581a7676ed5d70699cecd30056`

## Summary

- New commits: 8

## Commits

- [0fcab55](https://github.com/google/adk-js/commit/0fcab5503afa44012207b995864e59ff9012653d) feat(models): support Vertex AI model-optimizer endpoints in Gemini (#1350) (adk-foundry-bot, 2026-11-17)
- [3609c13](https://github.com/google/adk-js/commit/3609c13671e969e327fec86062632031c7c8be63) test(agents): verify loop agent finishes current sub-agent on escalation (#1349) (adk-foundry-bot, 2026-11-17)
- [199243d](https://github.com/google/adk-js/commit/199243dd7ad9cff94defd2b1d0ddc903d0fc04f8) feat(tools): support null/void return schemas and LangChain coroutine tools (#1340) (adk-foundry-bot, 2026-11-17)
- [6ec680e](https://github.com/google/adk-js/commit/6ec680ee752c0f2611e894bc8bbb4b897d3f138a) fix(core): tokenize memory queries and override path-level OpenAPI parameters (#1339) (adk-foundry-bot, 2026-11-17)
- [2988937](https://github.com/google/adk-js/commit/29889370bea5c0f88a5ced671af8f5fe65c0085a) test(runner): add unit tests for stateDelta and live tool execution (#1338) (adk-foundry-bot, 2026-11-16)
- [9171335](https://github.com/google/adk-js/commit/9171335f72072300f9f78dff5c096f10c8cbb948) feat(agents): add saveCredential and loadCredential to Context (#1334) (adk-foundry-bot, 2026-11-16)
- [29b98c2](https://github.com/google/adk-js/commit/29b98c2113d5b55aae6882d0bf58c5755cfcc3e9) feat(tools): add service account auth to GoogleApiTool and GoogleApiToolset (#1329) (adk-foundry-bot, 2026-11-16)
- [2378015](https://github.com/google/adk-js/commit/2378015a2e2d9e9df223101dd28a37ea01ea340b) fix(flows): deep-merge event actions and fix live/callback edges (#1333) (adk-foundry-bot, 2026-11-16)

## Changed Files

- `M	core/src/agents/context.ts`
- `M	core/src/agents/functions.ts`
- `M	core/src/agents/llm_agent.ts`
- `M	core/src/events/event_actions.ts`
- `M	core/src/memory/in_memory_memory_service.ts`
- `M	core/src/models/google_llm.ts`
- `M	core/src/sessions/state_write_order.ts`
- `M	core/src/tools/function_tool.ts`
- `M	core/src/tools/google_api_tool/google_api_tool.ts`
- `M	core/src/tools/google_api_tool/google_api_toolset.ts`
- `M	core/src/tools/openapi_tool/openapi_spec_parser/openapi_spec_parser.ts`
- `M	core/src/tools/openapi_tool/openapi_spec_parser/operation_parser.ts`
- `M	core/src/tools/openapi_tool/rest_api_tool.ts`
- `A	core/test/agents/context_test.ts`
- `M	core/test/agents/functions_test.ts`
- `M	core/test/agents/llm_agent_test.ts`
- `M	core/test/agents/loop_agent_test.ts`
- `M	core/test/agents/processors/content_processor_utils_test.ts`
- `M	core/test/agents/processors/content_request_processor_test.ts`
- `M	core/test/events/event_actions_test.ts`
- `M	core/test/memory/in_memory_memory_service_test.ts`
- `M	core/test/models/google_llm_test.ts`
- `M	core/test/runner/run_live_test.ts`
- `M	core/test/runner/runner_test.ts`
- `M	core/test/tools/agent_tool_test.ts`
- `M	core/test/tools/base_toolset_test.ts`
- `M	core/test/tools/computer_use/computer_use_tool_test.ts`
- `M	core/test/tools/computer_use/computer_use_toolset_test.ts`
- `M	core/test/tools/function_tool_test.ts`
- `M	core/test/tools/google_api_tool/google_api_tool_test.ts`
- `M	core/test/tools/google_api_tool/google_api_toolset_test.ts`
- `M	core/test/tools/google_api_tool/google_api_toolsets_test.ts`
- `M	core/test/tools/openapi_tool/openapi_spec_parser_test.ts`
- `M	docs/guides/README.md`
- `M	docs/guides/agents/index.md`
- `M	docs/guides/integrations/langchain/index.md`
- `M	docs/guides/memory/index.md`
- `M	docs/guides/models/index.md`
- `M	docs/guides/tools/google_api_tool/index.md`
- `M	docs/guides/tools/index.md`
- `M	docs/guides/tools/openapi_tool/index.md`
- `M	integrations/src/langchain/langchain_tool.ts`
- `M	integrations/test/langchain/langchain_tool_test.ts`
- `M	samples/agents/README.md`
- `M	samples/agents/agent.ts`
- `M	samples/tools/google_api_tool/README.md`
- `M	samples/tools/google_api_tool/agent.ts`
