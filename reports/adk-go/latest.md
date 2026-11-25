# ADK Go Daily Change Report

- Date (UTC): 2026-11-25
- Source: `google/adk-go`
- Latest SHA: `7abba5655551d344b8ec4c56a92f3578631bcf4c`
- Previous SHA: `e52983b4b9d29d873e061e52e10ff391135feced`

## Summary

- New commits: 7

## Commits

- [7abba56](https://github.com/google/adk-go/commit/7abba5655551d344b8ec4c56a92f3578631bcf4c) feat(mcptoolset,remoteagent): present the client certificate to Google API hosts (#2418) (wolo, 2026-11-25)
- [4de6a96](https://github.com/google/adk-go/commit/4de6a9667904f8fbc885950098525cd306f39e51) feat(llmagent,loadartifactstool): add OutputArtifact and versioned artifact loading (#1688) (Sasha, 2026-11-25)
- [97864da](https://github.com/google/adk-go/commit/97864da015410867e1cbc8a981123077066aec41) fix(configurable): require opt-in for stdio MCP configs (#2497) (ktsoator, 2026-11-25)
- [df0eec1](https://github.com/google/adk-go/commit/df0eec19d3c58812e7efa41531f193b72e4279b6) fix(agenttool): keep code artifacts out of structured replies (#2468) (wangshun, 2026-11-25)
- [3a53b39](https://github.com/google/adk-go/commit/3a53b396b622cb4e3768957d1b9d8f93c801136b) feat(version): report the hosting runtime in tracking headers (#2457) (wolo, 2026-11-25)
- [ba236dc](https://github.com/google/adk-go/commit/ba236dc90e5970564befba72daa40551cdb1c382) test: pin the panic text that a failed tool keeps from the model (#2487) (SandeepVijayarao, 2026-11-25)
- [0697df1](https://github.com/google/adk-go/commit/0697df183ce239b8f21e4253e220b4a454a40c72) fix(openaimodel): reject streamed function call events without item_id (#2483) (ocharrez, 2026-11-25)

## Changed Files

- `M	agent/llmagent/llm_agent_wrapper.go`
- `M	agent/llmagent/llm_agent_wrapper_test.go`
- `M	agent/llmagent/llmagent.go`
- `M	agent/llmagent/llmagent_saveoutput_test.go`
- `M	agent/remoteagent/v2/a2a_agent.go`
- `M	agent/remoteagent/v2/a2a_agent_test.go`
- `M	agent/remoteagent/v2/auth.go`
- `M	agent/remoteagent/v2/auth_test.go`
- `A	agent/remoteagent/v2/main_test.go`
- `A	agent/remoteagent/v2/mtls_test.go`
- `M	agent/workflowagents/sequentialagent/agent.go`
- `M	internal/artifact/artifacts.go`
- `M	internal/artifact/forwarding.go`
- `M	internal/configurable/configurable_utils.go`
- `M	internal/configurable/configurable_utils_test.go`
- `M	internal/credredirect/credredirect.go`
- `M	internal/credredirect/credredirect_test.go`
- `A	internal/googlemtls/googlemtls.go`
- `A	internal/googlemtls/googlemtls_test.go`
- `A	internal/googlemtls/googlemtlstest/googlemtlstest.go`
- `A	internal/googlemtls/handshake_test.go`
- `A	internal/googlemtls/main_test.go`
- `M	internal/llminternal/agent.go`
- `M	internal/llminternal/base_flow_test.go`
- `M	internal/llminternal/outputschema_processor.go`
- `M	internal/toolinternal/tool_test.go`
- `M	internal/version/tracking.go`
- `M	internal/version/tracking_test.go`
- `A	internal/version/versiontest/versiontest.go`
- `M	model/anthropicmodel/anthropicmodel.go`
- `M	model/anthropicmodel/anthropicmodel_test.go`
- `M	model/apigee/apigee_test.go`
- `M	model/gemini/context_cache.go`
- `M	model/gemini/context_cache_test.go`
- `M	model/gemini/gemini.go`
- `M	model/gemini/gemini_test.go`
- `M	model/openaimodel/internal/responses/model_test.go`
- `M	model/openaimodel/internal/responses/stream.go`
- `M	model/openaimodel/internal/responses/stream_test.go`
- `M	plugin/retryandreflect/plugin_test.go`
- `M	tool/agenttool/agent_tool.go`
- `M	tool/agenttool/agent_tool_artifacts_test.go`
- `M	tool/agenttool/agent_tool_test.go`
- `A	tool/agenttool/workflow_tool_panic_test.go`
- `M	tool/bigquerytoolset/client.go`
- `M	tool/bigquerytoolset/toolset_test.go`
- `M	tool/loadartifactstool/load_artifacts_tool.go`
- `M	tool/loadartifactstool/load_artifacts_tool_test.go`
- `A	tool/mcptoolset/main_test.go`
- `A	tool/mcptoolset/mtls_test.go`
- `M	tool/mcptoolset/set.go`
- `M	tool/mcptoolset/tracking.go`
- `M	tool/mcptoolset/tracking_test.go`
