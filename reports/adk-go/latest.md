# ADK Go Daily Change Report

- Date (UTC): 2026-11-16
- Source: `google/adk-go`
- Latest SHA: `02b1d0b5c73633f620653efb1e51beb9d48d1d74`
- Previous SHA: `9feb18b93a048e035a01dd2da688a8f28bd8a5fc`

## Summary

- New commits: 5

## Commits

- [02b1d0b](https://github.com/google/adk-go/commit/02b1d0b5c73633f620653efb1e51beb9d48d1d74) chore(main): release 2.8.0 (#2138) (ADK Go Bot, 2026-11-16)
- [a74c078](https://github.com/google/adk-go/commit/a74c078e7f31633bd5eb0921e6ee8e2515639e64) fix(llminternal): answer unknown tool calls the way adk-python does (#2316) (Sasha, 2026-11-16)
- [e6c1b63](https://github.com/google/adk-go/commit/e6c1b63c345e5758aa8b8ee2edfb5c4517ca4458) ci: run the Go workflow on pushes to the v3 branch (#2363) (wolo, 2026-11-16)
- [dece60a](https://github.com/google/adk-go/commit/dece60a02aeabcef50a6c263eb19c7a362a36e8f) test: tighten tests and comments for recent runner and tool fixes (#2319) (Sasha, 2026-11-16)
- [4d4d4d1](https://github.com/google/adk-go/commit/4d4d4d1774da18d3e5d8d590b0b77a0e612189b4) fix(llminternal): drop thought signatures from live history (#2261) (KVR Vishnu, 2026-11-16)

## Changed Files

- `M	.github/.release-please-manifest.json`
- `M	.github/workflows/go.yml`
- `M	CHANGELOG.md`
- `M	agent/llmagent/llm_agent_wrapper.go`
- `M	agent/llmagent/llmagent.go`
- `M	internal/llminternal/base_flow.go`
- `M	internal/llminternal/base_flow_test.go`
- `M	internal/llminternal/contents_processor.go`
- `M	internal/llminternal/contents_processor_test.go`
- `M	internal/llminternal/googlellm/live_connection.go`
- `M	internal/llminternal/googlellm/live_connection_test.go`
- `M	internal/llminternal/parallel_function_call_hitl_test.go`
- `M	internal/llminternal/streaming_tool_test.go`
- `M	internal/version/version.go`
- `M	runner/live_runner_test.go`
- `M	runner/run_node_test.go`
- `M	runner/runner_test.go`
- `M	server/adka2a/v2/parts.go`
- `M	server/adka2a/v2/parts_test.go`
- `M	tool/loadartifactstool/load_artifacts_tool.go`
- `M	tool/loadartifactstool/load_artifacts_tool_test.go`
