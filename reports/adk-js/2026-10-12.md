# ADK JS Daily Change Report

- Date (UTC): 2026-10-12
- Source: `google/adk-js`
- Latest SHA: `14c9c3d58b915dc834306f851bb25c71d3f243c5`
- Previous SHA: `86d1cfeff3b868e23ff8335475148c0ceb07b60f`

## Summary

- New commits: 11

## Commits

- [14c9c3d](https://github.com/google/adk-js/commit/14c9c3d58b915dc834306f851bb25c71d3f243c5) fix(dev): install the cli_create console spies per test (#1028) (adk-foundry-bot, 2026-10-12)
- [ee3e740](https://github.com/google/adk-js/commit/ee3e740d6467d39ac28d2edfe71032a0843b7c2c) fix(test): size the vitest worker heap ceiling off a measurement (#1027) (adk-foundry-bot, 2026-10-12)
- [2ad6c5e](https://github.com/google/adk-js/commit/2ad6c5ec2594ac2e2d5bb16c05a85f086104cadc) chore(dev): remove debug scaffolding from cli_deploy_agent_engine_test (#1026) (adk-foundry-bot, 2026-10-12)
- [ecb6bd1](https://github.com/google/adk-js/commit/ecb6bd13d69ad9e442d1936e5c23da08cd0d398e) feat(cli): bring cli to parity with adk-python v0.1.0 (#1049) (adk-foundry-bot, 2026-10-12)
- [94b547b](https://github.com/google/adk-js/commit/94b547be3a1807bcc7979044a9ad269b642453bf) feat(flows): bring flows to parity with adk-python v0.1.0 (#1048) (adk-foundry-bot, 2026-10-12)
- [6362192](https://github.com/google/adk-js/commit/63621924f009acd6421fce030b4c76d812148fd8) feat(tools): bring mcp_tool to parity with adk-python v0.1.0 (#1047) (adk-foundry-bot, 2026-10-12)
- [e4bb8ee](https://github.com/google/adk-js/commit/e4bb8ee66f966d95c85569401389e785f4736680) feat(tools): bring tools to parity with adk-python v0.1.0 (#1046) (adk-foundry-bot, 2026-10-12)
- [ce75d16](https://github.com/google/adk-js/commit/ce75d1639cb2cbb650a46ed90422daafc946705b) fix(models): respect explicit vertexai: false when enterprise env vars are set (#1044) (Varun-S10, 2026-10-12)
- [6eabc04](https://github.com/google/adk-js/commit/6eabc04c0569bc49dd98b177459a05646ba983b4) test: raise vitest coverage thresholds to the measured floor (#1024) (adk-foundry-bot, 2026-10-11)
- [83bf5e3](https://github.com/google/adk-js/commit/83bf5e34f7f24b5f962aa7fcdd21a422f3d2492e) test(memory): name the project and location constants in the memory bank test (#1023) (adk-foundry-bot, 2026-10-11)
- [7a8020c](https://github.com/google/adk-js/commit/7a8020cada4db3159c2a7d49dbe7d2b9a5b5f232) ci: check license headers in .mjs and .cjs files (#1022) (adk-foundry-bot, 2026-10-11)

## Changed Files

- `M	core/src/agents/functions.ts`
- `M	core/src/agents/invocation_context.ts`
- `M	core/src/agents/llm_agent.ts`
- `A	core/src/cli/cli_eval.ts`
- `A	core/src/cli/utils/envs.ts`
- `A	core/src/cli/utils/evals.ts`
- `A	core/src/cli/utils/logs.ts`
- `M	core/src/common.ts`
- `A	core/src/flows/llm_flows/audio_transcriber.ts`
- `M	core/src/index.ts`
- `M	core/src/models/google_llm.ts`
- `M	core/src/tools/agent_tool.ts`
- `A	core/src/tools/crewai_tool.ts`
- `M	core/src/tools/function_tool.ts`
- `A	core/src/tools/langchain_tool.ts`
- `M	core/src/tools/mcp/index.ts`
- `M	core/src/tools/mcp/mcp_session_manager.ts`
- `M	core/src/tools/mcp/mcp_toolset.ts`
- `M	core/src/tools/retrieval/base_retrieval_tool.ts`
- `A	core/src/tools/toolbox_tool.ts`
- `M	core/src/utils/gemini_schema_util.ts`
- `M	core/test/agents/functions_test.ts`
- `M	core/test/agents/llm_agent_test.ts`
- `A	core/test/cli/cli_eval_test.ts`
- `A	core/test/cli/utils/envs_test.ts`
- `A	core/test/cli/utils/evals_test.ts`
- `A	core/test/cli/utils/logs_test.ts`
- `A	core/test/flows/llm_flows/audio_transcriber_test.ts`
- `M	core/test/memory/vertex_ai_memory_bank_service_test.ts`
- `M	core/test/models/google_llm_test.ts`
- `M	core/test/tools/agent_tool_test.ts`
- `A	core/test/tools/crewai_tool_test.ts`
- `M	core/test/tools/function_tool_test.ts`
- `A	core/test/tools/langchain_tool_test.ts`
- `M	core/test/tools/mcp/mcp_session_manager_test.ts`
- `M	core/test/tools/mcp/mcp_toolset_test.ts`
- `M	core/test/tools/retrieval/base_retrieval_tool_test.ts`
- `A	core/test/tools/toolbox_tool_test.ts`
- `M	dev/src/cli/cli.ts`
- `M	dev/src/cli/cli_run.ts`
- `M	dev/src/cli/deploy/cli_deploy_cloud_run.ts`
- `M	dev/src/server/adk_api_server.ts`
- `M	dev/src/server/agent_graph.ts`
- `M	dev/test/cli/cli_create_test.ts`
- `M	dev/test/cli/cli_deploy_agent_engine_test.ts`
- `M	dev/test/cli/cli_deploy_cloud_run_test.ts`
- `M	dev/test/cli/cli_run_test.ts`
- `M	dev/test/cli/cli_test.ts`
- `M	dev/test/server/adk_api_server_test.ts`
- `M	dev/test/server/agent_graph_test.ts`
- `M	docs/guides/README.md`
- `A	docs/guides/cli/index.md`
- `A	docs/guides/flows/index.md`
- `A	docs/guides/tools/index.md`
- `A	docs/guides/tools/mcp_tool/index.md`
- `A	samples/cli/README.md`
- `A	samples/cli/agent.ts`
- `A	samples/flows/README.md`
- `A	samples/flows/agent.ts`
- `M	samples/tools/README.md`
- `A	samples/tools/agent.ts`
- `A	samples/tools/mcp_tool/README.md`
- `A	samples/tools/mcp_tool/agent.ts`
- `A	samples/tools/mcp_tool/mcp_server.mjs`
- `M	scripts/check_license.sh`
- `M	tests/integration/build_setup/ts_commonjs_native_addon/fake-onnxruntime-node/index.cjs`
- `M	tests/integration/build_setup/ts_esm_native_addon/fake-onnxruntime-node/index.cjs`
- `M	vitest.config.ts`
