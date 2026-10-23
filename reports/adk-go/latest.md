# ADK Go Daily Change Report

- Date (UTC): 2026-10-23
- Source: `google/adk-go`
- Latest SHA: `733b52570555653a768134ab827e01691be8d871`
- Previous SHA: `331c9c579fb179e4bde783724463d60f401a4efb`

## Summary

- New commits: 4

## Commits

- [733b525](https://github.com/google/adk-go/commit/733b52570555653a768134ab827e01691be8d871) feat(agentanalytics): add pre-built per-event BigQuery analytics views (#1791) (Haiyuan Cao, 2026-10-23)
- [5732578](https://github.com/google/adk-go/commit/5732578a97bea6d8d36e74e1ad7ac6c394fbfbf2) fix(agentanalytics): ExactlyOnceDelivery and DropStats follow-ups from #1790 (#1943) (Haiyuan Cao, 2026-10-23)
- [4df7bdd](https://github.com/google/adk-go/commit/4df7bdda94fd7beca43e5d5fb27605381d384cda) fix(agentanalytics): preserve invocation spans for late callbacks (#1911) (Jabrail, 2026-10-23)
- [03e4117](https://github.com/google/adk-go/commit/03e4117750cb4a90fedd1715caa92e55261ca216) feat(agentanalytics): add DropStats, ExactlyOnceDelivery, and schema setup hardening (#1790) (Haiyuan Cao, 2026-10-22)

## Changed Files

- `M	plugin/agentanalytics/batch_processor.go`
- `M	plugin/agentanalytics/batch_processor_test.go`
- `M	plugin/agentanalytics/bigquery_agent_analytics_plugin.go`
- `M	plugin/agentanalytics/bigquery_agent_analytics_plugin_test.go`
- `M	plugin/agentanalytics/config.go`
- `M	plugin/agentanalytics/events.go`
- `M	plugin/agentanalytics/go.mod`
- `A	plugin/agentanalytics/late_callbacks_test.go`
- `M	plugin/agentanalytics/schema.go`
- `A	plugin/agentanalytics/schema_upgrade.go`
- `A	plugin/agentanalytics/schema_upgrade_test.go`
- `M	plugin/agentanalytics/trace_manager.go`
- `M	plugin/agentanalytics/trace_manager_test.go`
- `A	plugin/agentanalytics/views.go`
- `A	plugin/agentanalytics/views_test.go`
