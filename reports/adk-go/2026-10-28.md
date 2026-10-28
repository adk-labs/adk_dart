# ADK Go Daily Change Report

- Date (UTC): 2026-10-28
- Source: `google/adk-go`
- Latest SHA: `017295fba0037cfd60256f327337a90bcb8cfeed`
- Previous SHA: `19707a2660a8dd7b8ffb32837027253ed2f29dd1`

## Summary

- New commits: 6

## Commits

- [017295f](https://github.com/google/adk-go/commit/017295fba0037cfd60256f327337a90bcb8cfeed) fix(agentanalytics): tidy span bookkeeping, comments and tests (#1953) (Haiyuan Cao, 2026-10-28)
- [6f67c5a](https://github.com/google/adk-go/commit/6f67c5ade58abd478284283cc948463771d0e943) fix(llminternal): match close code 1008 by type in isResumable (#1993) (Jan Wojtas, 2026-10-28)
- [4bd9638](https://github.com/google/adk-go/commit/4bd9638d01cfe49df79c196d3322b2b451e34ed8) fix(agentanalytics): pause run-end uploads when any batch's upload stalls (#1955) (Haiyuan Cao, 2026-10-28)
- [59042e5](https://github.com/google/adk-go/commit/59042e5565ff5595eecbf9df01ebbf13d7e5874c) docs(artifact): deprecate SaveRequest.Version (#1985) (Jan Wojtas, 2026-10-28)
- [e040707](https://github.com/google/adk-go/commit/e0407070d6bc213624e76eedf2f777910c901c4a) feat(model/anthropicmodel): add Anthropic Claude model support (#1866) (Scott Mansfield, 2026-10-28)
- [b7049b8](https://github.com/google/adk-go/commit/b7049b87a9e6878912b8a116a370497ee65190ed) fix(agentanalytics): report the right terminal row in more failure cases (#1952) (Haiyuan Cao, 2026-10-27)

## Changed Files

- `M	AGENTS.md`
- `M	artifact/service.go`
- `A	examples/anthropic/README.md`
- `A	examples/anthropic/main.go`
- `M	go.mod`
- `M	go.sum`
- `M	internal/llminternal/base_flow.go`
- `M	internal/llminternal/base_flow_live_test.go`
- `M	internal/llminternal/base_flow_resumable_test.go`
- `A	model/anthropicmodel/anthropicmodel.go`
- `A	model/anthropicmodel/anthropicmodel_test.go`
- `A	model/anthropicmodel/cache.go`
- `A	model/anthropicmodel/config.go`
- `A	model/anthropicmodel/doc.go`
- `A	model/anthropicmodel/errors.go`
- `A	model/anthropicmodel/request.go`
- `A	model/anthropicmodel/response.go`
- `A	model/anthropicmodel/stream.go`
- `A	model/anthropicmodel/testdata/TestAgentRunner_MultiTurnImageAndTool.httprr`
- `A	model/anthropicmodel/testdata/TestGenerate_Anthropic.httprr`
- `A	model/anthropicmodel/testdata/TestGenerate_Vertex.httprr`
- `A	model/anthropicmodel/thinking.go`
- `A	model/anthropicmodel/tools.go`
- `M	plugin/agentanalytics/batch_processor.go`
- `M	plugin/agentanalytics/batch_processor_test.go`
- `M	plugin/agentanalytics/bigquery_agent_analytics_plugin.go`
- `M	plugin/agentanalytics/config.go`
- `M	plugin/agentanalytics/gcs_offloader.go`
- `M	plugin/agentanalytics/gcs_offloader_test.go`
- `M	plugin/agentanalytics/json_formatter.go`
- `M	plugin/agentanalytics/late_callbacks_test.go`
- `M	plugin/agentanalytics/trace_manager.go`
- `M	plugin/agentanalytics/trace_manager_test.go`
