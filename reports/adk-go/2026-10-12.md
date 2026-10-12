# ADK Go Daily Change Report

- Date (UTC): 2026-10-12
- Source: `google/adk-go`
- Latest SHA: `40d37cad8feffd20f6790961a604789b9b5049ac`
- Previous SHA: `987c7bc0bed6af5a4bae305df54c00019033d6d0`

## Summary

- New commits: 12

## Commits

- [40d37ca](https://github.com/google/adk-go/commit/40d37cad8feffd20f6790961a604789b9b5049ac) Align vertexai session service via ADK REST API with other impl (#1571) (Karol Droste, 2026-10-12)
- [bd42144](https://github.com/google/adk-go/commit/bd421447f90c60bfe08a411f4f7a2bf805075169) fix(model/gemini): turn off the genai SDK's automatic continuation (#1813) (João Westerberg, 2026-10-12)
- [01a97e7](https://github.com/google/adk-go/commit/01a97e7502a56bc658c963cbd0617e68c6a04587) chore(deps): bump google.golang.org/grpc (#1814) (dependabot[bot], 2026-10-12)
- [457663d](https://github.com/google/adk-go/commit/457663d29337cd844a8d4c487411ab45b9006505) fix(model/gemini): resume a MAX_TOKENS stop when the request sets no maxOutputTokens (#1759) (João Westerberg, 2026-10-12)
- [7397a5d](https://github.com/google/adk-go/commit/7397a5dec303efbbc0604868a86edd094d885fce) fix(loopagent): return when there are no sub-agents (#1780) (Anzal Husain Abidi, 2026-10-12)
- [c4eb00b](https://github.com/google/adk-go/commit/c4eb00bc6e59b212968fe8f8375322a36766a143) feat(exp): add the experimental /apps/{app_name}/app-info endpoint (#1404) (Jan Wojtas, 2026-10-12)
- [e0edbfb](https://github.com/google/adk-go/commit/e0edbfbb3892014ca2d4f45f4f3ab41808ba2e91) docs(mcptoolset): fix constructor example and schema comment (#1779) (ktsoator, 2026-10-12)
- [1862aae](https://github.com/google/adk-go/commit/1862aaea60724b16784a55c01d51edadb2629470) fix(llminternal): guard nil first candidate in streaming aggregator (#1802) (PratikDhanave, 2026-10-12)
- [212cc58](https://github.com/google/adk-go/commit/212cc58e6739e7503ce641bb30e37ee41218e3a4) docs(telemetry): fix StartNodeSpan doc for invoke_workflow (#1805) (PratikDhanave, 2026-10-12)
- [bfaab17](https://github.com/google/adk-go/commit/bfaab17b5edeec6c6c04be17e8613b5fdde2a161) fix(agenttool): wrap the runner.New error instead of discarding it (#1803) (PratikDhanave, 2026-10-12)
- [a3afd7f](https://github.com/google/adk-go/commit/a3afd7f99f31f0720c0e09e201e23717571d02e2) fix(llminternal): correct misleading "global" in appendInstructions error (#1804) (PratikDhanave, 2026-10-12)
- [7245ee5](https://github.com/google/adk-go/commit/7245ee5cf12104b770afa9d8ca501d6bc8fa1eb1) chore(deps): bump the go-minor-patch group with 12 updates (#1798) (dependabot[bot], 2026-10-12)

## Changed Files

- `M	AGENTS.md`
- `M	CONTRIBUTING.md`
- `M	agent/workflowagents/loopagent/agent.go`
- `M	agent/workflowagents/loopagent/agent_test.go`
- `A	exp/appinfo/appinfo.go`
- `A	exp/appinfo/appinfo_test.go`
- `A	exp/appinfo/handler.go`
- `A	exp/appinfo/handler_test.go`
- `A	exp/appinfo/launcher.go`
- `A	exp/appinfo/launcher_test.go`
- `A	exp/doc.go`
- `M	go.mod`
- `M	go.sum`
- `M	internal/llminternal/instruction_processor.go`
- `M	internal/llminternal/stream_aggregator.go`
- `M	internal/llminternal/stream_aggregator_test.go`
- `M	internal/telemetry/node_tracing.go`
- `A	internal/workflowwalk/walk.go`
- `M	model/gemini/continuation.go`
- `M	model/gemini/continuation_test.go`
- `M	model/gemini/gemini.go`
- `M	plugin/agentanalytics/go.mod`
- `M	plugin/agentanalytics/go.sum`
- `M	session/service.go`
- `M	session/vertexai/delete_ownership_test.go`
- `M	session/vertexai/notfound_test.go`
- `M	session/vertexai/vertexai_client.go`
- `M	tool/agenttool/agent_tool.go`
- `M	tool/mcptoolset/set.go`
- `M	tool/mcptoolset/tool.go`
- `A	workflow/walk.go`
- `A	workflow/walk_test.go`
