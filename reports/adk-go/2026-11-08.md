# ADK Go Daily Change Report

- Date (UTC): 2026-11-08
- Source: `google/adk-go`
- Latest SHA: `dba8afa2bc3a54e13731ac6d18592edcba4c7530`
- Previous SHA: `5d03ab689207e5638b2d3ca700d404b6417cf0f6`

## Summary

- New commits: 7

## Commits

- [dba8afa](https://github.com/google/adk-go/commit/dba8afa2bc3a54e13731ac6d18592edcba4c7530) fix(llminternal): show the user's answer to another agent's call as context (#2202) (Gangavarapu Vivek, 2026-11-08)
- [c4b057c](https://github.com/google/adk-go/commit/c4b057c5854f0061ee71be7ddc316f1e8ecbbb9b) feat(tool/bigquerytoolset): add the table tools (#2201) (Gangavarapu Vivek, 2026-11-08)
- [4d841ab](https://github.com/google/adk-go/commit/4d841abaefa6c641395dac09956e8d8350435724) fix(remoteagent): return errors instead of error events (#1740) (Gangavarapu Vivek, 2026-11-08)
- [c00807e](https://github.com/google/adk-go/commit/c00807e66bbd02e87fe612dcd680b1e735a71f2d) fix(agentengine): preserve fractional seconds in event timestamp encoding (#2199) (sundeep8967, 2026-11-08)
- [d9d7c3b](https://github.com/google/adk-go/commit/d9d7c3ba32963988d2ccc81b9f4d49daefcd7bb1) chore(deps): bump the go-minor-patch group with 7 updates (#2108) (dependabot[bot], 2026-11-07)
- [c585264](https://github.com/google/adk-go/commit/c5852645d0e8fedf124f687e59d986526a38216f) feat(client/agentengine): stream-query client for Agent Runtime (#1989) (wolo, 2026-11-07)
- [51bc7ec](https://github.com/google/adk-go/commit/51bc7ec593e7ab86fde7cf303aaa1bbdd1a5b7eb) fix(workflowagents): skip siblings when resuming a nested graph workflow (#2188) (Gangavarapu Vivek, 2026-11-08)

## Changed Files

- `M	agent/remoteagent/a2a_agent.go`
- `M	agent/remoteagent/v2/a2a_agent.go`
- `M	agent/remoteagent/v2/a2a_agent_run_processor.go`
- `M	agent/remoteagent/v2/a2a_agent_test.go`
- `M	agent/remoteagent/v2/auth.go`
- `M	agent/remoteagent/v2/auth_test.go`
- `M	agent/workflowagents/loopagent/agent.go`
- `M	agent/workflowagents/parallelagent/agent.go`
- `M	agent/workflowagents/sequentialagent/agent.go`
- `M	agent/workflowagents/sequentialagent/agent_test.go`
- `A	client/agentengine/agentengine.go`
- `A	client/agentengine/agentengine_test.go`
- `A	client/agentengine/example_test.go`
- `A	client/agentengine/jsonl.go`
- `A	client/agentengine/jsonl_test.go`
- `A	client/agentengine/stream.go`
- `A	client/agentengine/stream_test.go`
- `M	go.mod`
- `M	go.sum`
- `M	internal/llminternal/contents_processor.go`
- `A	internal/llminternal/foreign_function_response_test.go`
- `A	internal/utils/graph_resume.go`
- `M	model/anthropicmodel/anthropicmodel_test.go`
- `M	model/anthropicmodel/config.go`
- `M	runner/runner.go`
- `M	runner/workflow_function_response_test.go`
- `M	server/agentengine/internal/helper/encode.go`
- `M	server/agentengine/internal/helper/encode_test.go`
- `A	tool/bigquerytoolset/descriptions/get_table_info.txt`
- `A	tool/bigquerytoolset/descriptions/list_table_ids.txt`
- `M	tool/bigquerytoolset/doc.go`
- `M	tool/bigquerytoolset/metadata.go`
- `M	tool/bigquerytoolset/toolset.go`
- `M	tool/bigquerytoolset/toolset_test.go`
