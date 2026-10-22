# ADK JS Daily Change Report

- Date (UTC): 2026-10-22
- Source: `google/adk-js`
- Latest SHA: `f5af3834f5bb6eda89818c69e8782d4740435581`
- Previous SHA: `df491a96e70c33061aa7aa715ced4f884efa89bb`

## Summary

- New commits: 8

## Commits

- [f5af383](https://github.com/google/adk-js/commit/f5af3834f5bb6eda89818c69e8782d4740435581) test(tools): type the load_web_page DNS and fetch mocks (#1097) (adk-foundry-bot, 2026-10-22)
- [934d6bf](https://github.com/google/adk-js/commit/934d6bf981cc8391dcae37632bbf18fd857233f5) fix(code-executors): define crop in the data-file helper (#994) (JOJO, 2026-10-22)
- [48e5423](https://github.com/google/adk-js/commit/48e5423b7c7a0daca84df420f996e498087218f5) fix(core): remove orphaned fragment from onToolErrorCallback JSDoc (#1019) (adk-foundry-bot, 2026-10-21)
- [dc02f45](https://github.com/google/adk-js/commit/dc02f453518db7078396e4121d568a179619935c) fix(core): inject the text of inlineData artifacts into instructions (#1116) (ni, 2026-10-21)
- [64379d9](https://github.com/google/adk-js/commit/64379d94276092a744241d706f92ee061c371615) test(tools): add unit tests for MCPToolset.close and MCPTool declaration (#1114) (Scott Mansfield, 2026-10-21)
- [687a201](https://github.com/google/adk-js/commit/687a2012a57857b0c1e2af3fdf89d4b110d796dd) feat: port adk-python v1.0.0 changes to examples, runners, tools/apihub_tool (+1 more) (#1112) (Scott Mansfield, 2026-10-21)
- [c33d2de](https://github.com/google/adk-js/commit/c33d2de61a19f7d30ac50e328161cb5a8f9b2530) feat(agents): port adk-python v1.0.0 changes to agents (#1109) (Scott Mansfield, 2026-10-21)
- [f9ffb18](https://github.com/google/adk-js/commit/f9ffb18eed7974a6a476b9dd6312b03dca206b09) feat(tools): port adk-python v1.0.0 changes to tools (#1108) (Scott Mansfield, 2026-10-21)

## Changed Files

- `M	core/src/agents/instructions.ts`
- `M	core/src/agents/llm_agent.ts`
- `M	core/src/agents/processors/code_execution_request_processor.ts`
- `M	core/src/common.ts`
- `M	core/src/plugins/base_plugin.ts`
- `M	core/src/tools/apihub_tool/apihub_toolset.ts`
- `M	core/src/tools/langchain_tool.ts`
- `M	core/src/tools/load_artifacts_tool.ts`
- `M	core/src/tools/load_memory_tool.ts`
- `M	core/src/tools/openapi_tool/openapi_toolset.ts`
- `A	core/src/tools/toolbox_toolset.ts`
- `M	core/test/agents/instructions_test.ts`
- `M	core/test/agents/llm_agent_test.ts`
- `M	core/test/agents/parallel_agent_test.ts`
- `M	core/test/agents/processors/code_execution_request_processor_test.ts`
- `M	core/test/runner/run_live_test.ts`
- `M	core/test/tools/agent_tool_test.ts`
- `M	core/test/tools/apihub_tool/apihub_toolset_test.ts`
- `A	core/test/tools/base_tool_test.ts`
- `M	core/test/tools/function_tool_test.ts`
- `M	core/test/tools/langchain_tool_test.ts`
- `M	core/test/tools/load_web_page_test.ts`
- `M	core/test/tools/mcp/mcp_tool_test.ts`
- `M	core/test/tools/mcp/mcp_toolset_test.ts`
- `M	core/test/tools/openapi_tool/openapi_toolset_test.ts`
- `A	core/test/tools/toolbox_toolset_test.ts`
- `M	docs/guides/tools/apihub_tool/index.md`
- `M	docs/guides/tools/index.md`
- `M	samples/tools/agent.ts`
