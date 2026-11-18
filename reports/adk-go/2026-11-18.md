# ADK Go Daily Change Report

- Date (UTC): 2026-11-18
- Source: `google/adk-go`
- Latest SHA: `f01ccf8724d45c25e6d0a0edac01a04945f3d147`
- Previous SHA: `012af4d94fb0ad67713180a4233d63c5fd520d1c`

## Summary

- New commits: 12

## Commits

- [f01ccf8](https://github.com/google/adk-go/commit/f01ccf8724d45c25e6d0a0edac01a04945f3d147) fix(auth): keep the ID token exchange out of SDK debug logs (#2396) (wolo, 2026-11-18)
- [dfe94f9](https://github.com/google/adk-go/commit/dfe94f9cb4e8061fd782c611c5a5d8242802324d) chore(deps): bump the go-minor-patch group across 1 directory with 9 updates (#2410) (dependabot[bot], 2026-11-18)
- [4a56d9f](https://github.com/google/adk-go/commit/4a56d9f2addcf9896a4104538119f561c59eedeb) fix(adka2a): order task history chronologically for input-required tasks (#2407) (wolo, 2026-11-18)
- [b9a5db9](https://github.com/google/adk-go/commit/b9a5db9c924cdf8220d09059814172f43ce4db01) fix(mcptoolset): keep the Config.Auth credential on the endpoint's origin across redirects (#1986) (wolo, 2026-11-18)
- [0b6973c](https://github.com/google/adk-go/commit/0b6973ca52816e887f0f4a5e3adc7060996deb2f) feat(tool/skilltoolset/skill): let a file-system listing skip invalid skills (#2390) (Artsiom Shut, 2026-11-18)
- [8224be1](https://github.com/google/adk-go/commit/8224be177a7bd78e045d08c94b850cb12a4de6ff) chore(agentanalytics): address #2020 post-merge review nits (#2388) (Haiyuan Cao, 2026-11-18)
- [6e73acc](https://github.com/google/adk-go/commit/6e73accaf9b3b333d050b7a6889a3c7a2bc8431f) fix(agentanalytics): redact compound and state-prefixed sensitive keys (#2250) (Haiyuan Cao, 2026-11-18)
- [6730502](https://github.com/google/adk-go/commit/673050266d9bf329f8cc46a93720ab27ba14ca46) fix(agentanalytics): scope lookalike parent resolution to active goroutine (#2379) (Haiyuan Cao, 2026-11-18)
- [f423f02](https://github.com/google/adk-go/commit/f423f0299b5d64be0b3ff171c245cb2a1180839a) fix(agentanalytics): align checkpoint gating, MCP isError tool results, and empty error messages (#2047) (#2178) (Haiyuan Cao, 2026-11-18)
- [b019ecc](https://github.com/google/adk-go/commit/b019ecc3f628a97c5b64f930a0c5a43f6182a8ce) fix(agentanalytics): isolate BigQuery RowErrors and track RowErrorDrops (#2376) (Haiyuan Cao, 2026-11-18)
- [0cc3907](https://github.com/google/adk-go/commit/0cc3907bcf3af14264b96645f6f021b033a6752a) refactor(auth): build the ADC paths on cloud.google.com/go/auth (#2378) (wolo, 2026-11-18)
- [2924008](https://github.com/google/adk-go/commit/2924008fb6269ec37419ce31a182f16e8c043b90) fix(agentanalytics): match an error-ended tool call to its own attempt (#2377) (Haiyuan Cao, 2026-11-18)

## Changed Files

- `M	agent/remoteagent/v2/a2a_e2e_test.go`
- `M	agent/remoteagent/v2/auth.go`
- `M	agent/remoteagent/v2/auth_test.go`
- `M	auth/doc.go`
- `M	auth/gcp/client.go`
- `M	auth/gcp/client_test.go`
- `A	auth/gcp/export_test.go`
- `M	auth/gcp/provider.go`
- `M	auth/gcp/provider_internal_test.go`
- `M	auth/gcp/provider_test.go`
- `M	auth/providers.go`
- `A	auth/providers_idtoken_test.go`
- `M	auth/providers_internal_test.go`
- `M	go.mod`
- `M	go.sum`
- `A	internal/credredirect/credredirect.go`
- `A	internal/credredirect/credredirect_test.go`
- `M	plugin/agentanalytics/batch_processor.go`
- `M	plugin/agentanalytics/batch_processor_test.go`
- `M	plugin/agentanalytics/bigquery_agent_analytics_plugin.go`
- `M	plugin/agentanalytics/bigquery_agent_analytics_plugin_test.go`
- `M	plugin/agentanalytics/config.go`
- `M	plugin/agentanalytics/doc.go`
- `M	plugin/agentanalytics/events.go`
- `M	plugin/agentanalytics/events_test.go`
- `M	plugin/agentanalytics/json_formatter.go`
- `M	plugin/agentanalytics/json_formatter_test.go`
- `M	plugin/agentanalytics/redaction.go`
- `A	plugin/agentanalytics/redaction_backstop.go`
- `A	plugin/agentanalytics/redaction_base_parity_test.go`
- `A	plugin/agentanalytics/redaction_keys.go`
- `A	plugin/agentanalytics/redaction_nested.go`
- `A	plugin/agentanalytics/redaction_regression_test.go`
- `A	plugin/agentanalytics/redaction_scanners.go`
- `A	plugin/agentanalytics/redaction_spans.go`
- `A	plugin/agentanalytics/redaction_test.go`
- `A	plugin/agentanalytics/redaction_uri.go`
- `A	plugin/agentanalytics/testdata/redaction_base_corpus.json`
- `M	plugin/agentanalytics/trace_manager.go`
- `M	plugin/agentanalytics/trace_manager_test.go`
- `M	plugin/agentanalytics/views_test.go`
- `M	tool/mcptoolset/client.go`
- `A	tool/mcptoolset/redirect_test.go`
- `M	tool/mcptoolset/set.go`
- `M	tool/mcptoolset/set_test.go`
- `M	tool/skilltoolset/skill/filesystem_source.go`
- `M	tool/skilltoolset/skill/filesystem_source_test.go`
