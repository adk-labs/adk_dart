# ADK Go Daily Change Report

- Date (UTC): 2026-10-16
- Source: `google/adk-go`
- Latest SHA: `c7ed87daa909e7563d3167e57daedee55f557d91`
- Previous SHA: `c935e6da519cd9b743ff0aeabcadd179cb15395c`

## Summary

- New commits: 5

## Commits

- [c7ed87d](https://github.com/google/adk-go/commit/c7ed87daa909e7563d3167e57daedee55f557d91) feat(mcptoolset): identify ADK in the User-Agent of MCP HTTP requests (#1862) (wolo, 2026-10-16)
- [1d2f545](https://github.com/google/adk-go/commit/1d2f5456649f21ac6a689cec5668c74b58297430) fix(agenttool): preserve code output in sub-agent results (#1860) (ktsoator, 2026-10-16)
- [7b10fa8](https://github.com/google/adk-go/commit/7b10fa82e6f3e297df4d9d5d99a7a58f293295f1) docs(compaction): list the GenerateContentConfig fields the summarizer uses (#1828) (Karol Piotrowicz, 2026-10-16)
- [b595778](https://github.com/google/adk-go/commit/b595778e9ef2a45be2e439a27b83e31722f83413) refactor(workflow): remove redundant goroutine in scheduleRetry (#1849) (moodbased, 2026-10-16)
- [900e2fa](https://github.com/google/adk-go/commit/900e2fa4907fa9825f708433ff162f6281069249) docs(loopagent): say the context is checked before each pass (#1861) (Anzal Husain Abidi, 2026-10-16)

## Changed Files

- `M	agent/workflowagents/loopagent/agent.go`
- `A	internal/version/tracking.go`
- `A	internal/version/tracking_test.go`
- `M	model/gemini/gemini.go`
- `M	runner/runner.go`
- `M	session/compaction/llm_summarizer.go`
- `M	tool/agenttool/agent_tool.go`
- `M	tool/agenttool/agent_tool_test.go`
- `M	tool/mcptoolset/set.go`
- `A	tool/mcptoolset/tracking.go`
- `A	tool/mcptoolset/tracking_test.go`
- `M	tool/mcptoolset/transport_config_test.go`
- `M	workflow/scheduler.go`
