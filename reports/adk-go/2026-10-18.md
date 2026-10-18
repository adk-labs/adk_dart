# ADK Go Daily Change Report

- Date (UTC): 2026-10-18
- Source: `google/adk-go`
- Latest SHA: `90efa8d01506e26f142d2855d3559fa9bb76722e`
- Previous SHA: `74faa9ab6bf58b47653ed275f4aa86a93e76280a`

## Summary

- New commits: 3

## Commits

- [90efa8d](https://github.com/google/adk-go/commit/90efa8d01506e26f142d2855d3559fa9bb76722e) fix(agent): record artifact-only deltas from before/after agent callbacks (#1878) (Anzal Husain Abidi, 2026-10-18)
- [225454b](https://github.com/google/adk-go/commit/225454bcd3fd7d81ee9c02af7fecadca751936bd) fix(llminternal): record model callback artifact saves on the event (#1800) (Gangavarapu Vivek, 2026-10-18)
- [fd32d28](https://github.com/google/adk-go/commit/fd32d286d3971101f8aa14017a3eec291cd8e87c) feat(agentanalytics): add concurrency-safe trace manager, latency_ms, and streaming TTFT (#1787) (Haiyuan Cao, 2026-10-18)

## Changed Files

- `M	agent/agent.go`
- `M	agent/agent_test.go`
- `A	agent/llmagent/model_callback_artifact_test.go`
- `M	internal/llminternal/base_flow.go`
- `M	plugin/agentanalytics/bigquery_agent_analytics_plugin.go`
- `M	plugin/agentanalytics/bigquery_agent_analytics_plugin_test.go`
- `M	plugin/agentanalytics/schema.go`
- `A	plugin/agentanalytics/trace_manager.go`
- `A	plugin/agentanalytics/trace_manager_test.go`
