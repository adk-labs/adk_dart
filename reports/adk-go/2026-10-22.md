# ADK Go Daily Change Report

- Date (UTC): 2026-10-22
- Source: `google/adk-go`
- Latest SHA: `331c9c579fb179e4bde783724463d60f401a4efb`
- Previous SHA: `f54a8cd890718543bf80d4c3aa2666e688a3d2e5`

## Summary

- New commits: 6

## Commits

- [331c9c5](https://github.com/google/adk-go/commit/331c9c579fb179e4bde783724463d60f401a4efb) feat(agentanalytics): pause GCS uploads after batch timeout and bound run-end write timeout deferral (#1936) (Haiyuan Cao, 2026-10-22)
- [03a62c3](https://github.com/google/adk-go/commit/03a62c3f285204f62b6827bbdf7957223347f1b4) fix(agentanalytics): never mark workflow agents taskDelegated (#1935) (Haiyuan Cao, 2026-10-22)
- [f7db1f4](https://github.com/google/adk-go/commit/f7db1f4a498781410c3cc032f96c7a2d96930bff) fix(agentanalytics): preserve live spans when tasks resume (#1910) (Jabrail, 2026-10-22)
- [889816b](https://github.com/google/adk-go/commit/889816b7288374920efedbae783496153205f1c2) chore: update Go version requirements in documentation (#1926) (ktsoator, 2026-10-22)
- [3c175ba](https://github.com/google/adk-go/commit/3c175bad1239d30b20fde7fcd3538b2a36dde748) feat(agentanalytics): add race-free GCS multimodal offloading and ObjectRef support (#1789) (Haiyuan Cao, 2026-10-21)
- [c240664](https://github.com/google/adk-go/commit/c240664ffbbda7bdf4f5adbc5684c489bfd99647) fix(agentanalytics): redact credentials when a value ends in a key name (#1863) (Haiyuan Cao, 2026-10-21)

## Changed Files

- `M	README.md`
- `M	examples/bidi/README.md`
- `M	plugin/agentanalytics/batch_processor.go`
- `M	plugin/agentanalytics/batch_processor_test.go`
- `M	plugin/agentanalytics/bigquery_agent_analytics_plugin.go`
- `M	plugin/agentanalytics/bigquery_agent_analytics_plugin_test.go`
- `M	plugin/agentanalytics/config.go`
- `A	plugin/agentanalytics/gcs_offloader.go`
- `A	plugin/agentanalytics/gcs_offloader_test.go`
- `M	plugin/agentanalytics/go.mod`
- `M	plugin/agentanalytics/go.sum`
- `M	plugin/agentanalytics/json_formatter.go`
- `M	plugin/agentanalytics/json_formatter_test.go`
- `A	plugin/agentanalytics/norace_test.go`
- `A	plugin/agentanalytics/race_test.go`
- `M	plugin/agentanalytics/redaction.go`
- `M	plugin/agentanalytics/trace_manager.go`
- `M	plugin/agentanalytics/trace_manager_test.go`
