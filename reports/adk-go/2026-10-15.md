# ADK Go Daily Change Report

- Date (UTC): 2026-10-15
- Source: `google/adk-go`
- Latest SHA: `c935e6da519cd9b743ff0aeabcadd179cb15395c`
- Previous SHA: `72e40cdee98c00ca8b5c14243d84c0f3b6e13a59`

## Summary

- New commits: 7

## Commits

- [c935e6d](https://github.com/google/adk-go/commit/c935e6da519cd9b743ff0aeabcadd179cb15395c) test(llminternal): match isResumable's doc and test table to the errors it sees (#1750) (Harshit Wandhare, 2026-10-15)
- [7b1db95](https://github.com/google/adk-go/commit/7b1db9555e9d2c09ab09c3760c9905c607725b90) test(model/gemini): pin the last citation and accepting AutomaticContinuation (#1825) (João Westerberg, 2026-10-15)
- [ac0388f](https://github.com/google/adk-go/commit/ac0388f73cd0bab01a432af527771e7645e3269b) fix(llminternal): prevent silent context degradation by propagating systemic state failures (#1748) (Karthik Thota, 2026-10-15)
- [6ed5dd0](https://github.com/google/adk-go/commit/6ed5dd08a3e9630861ba8a6663481e698f25e270) feat(runner): bound model calls per invocation with RunConfig.MaxLLMCalls (#1412) (Venkat Ramachandran, 2026-10-15)
- [9a43519](https://github.com/google/adk-go/commit/9a43519e401f0b25e179b133aaeb5bd550f7c379) fix(loopagent): stop on context cancellation (#1810) (Anzal Husain Abidi, 2026-10-15)
- [66cdc9a](https://github.com/google/adk-go/commit/66cdc9a08164d67667767d5505da0df001f2a50a) feat(agentanalytics): align schema, event vocabulary, redaction, and core contract with adk-python (#1786) (Haiyuan Cao, 2026-10-15)
- [b15de1c](https://github.com/google/adk-go/commit/b15de1cd4a92653a28eb95c48f0d9ec9558ac7ec) docs(artifact): fix service references in doc comments (#1775) (ktsoator, 2026-10-15)

## Changed Files

- `M	agent/run_config.go`
- `M	agent/workflowagents/loopagent/agent.go`
- `M	agent/workflowagents/loopagent/agent_test.go`
- `M	artifact/service.go`
- `A	internal/agent/runconfig/limits.go`
- `A	internal/agent/runconfig/limits_test.go`
- `M	internal/agent/runconfig/run_config.go`
- `M	internal/llminternal/base_flow.go`
- `M	internal/llminternal/base_flow_resumable_test.go`
- `M	internal/llminternal/instruction_processor.go`
- `M	internal/llminternal/instruction_processor_test.go`
- `M	model/gemini/continuation_test.go`
- `M	model/openaimodel/doc.go`
- `M	model/openaimodel/internal/completions/request_test.go`
- `M	model/openaimodel/internal/responses/request_test.go`
- `A	plugin/agentanalytics/arrow_test_helper_test.go`
- `M	plugin/agentanalytics/batch_processor.go`
- `M	plugin/agentanalytics/batch_processor_test.go`
- `M	plugin/agentanalytics/bigquery_agent_analytics_plugin.go`
- `M	plugin/agentanalytics/bigquery_agent_analytics_plugin_test.go`
- `M	plugin/agentanalytics/config.go`
- `M	plugin/agentanalytics/go.mod`
- `M	plugin/agentanalytics/json_formatter.go`
- `M	plugin/agentanalytics/json_formatter_test.go`
- `A	plugin/agentanalytics/redaction.go`
- `M	plugin/agentanalytics/schema.go`
- `A	runner/max_llm_calls_test.go`
- `M	runner/run_node.go`
- `M	runner/runner.go`
- `M	tool/agenttool/agent_tool.go`
- `A	tool/agenttool/agent_tool_limits_test.go`
