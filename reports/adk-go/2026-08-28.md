# ADK Go Daily Change Report

- Date (UTC): 2026-08-28
- Source: `google/adk-go`
- Latest SHA: `0da17d5183cc7affd4bdb7b4075f9e264bb598be`
- Previous SHA: `245ba284ed51f0f58355a6233f0b1ae01f252160`

## Summary

- New commits: 13

## Commits

- [0da17d5](https://github.com/google/adk-go/commit/0da17d5183cc7affd4bdb7b4075f9e264bb598be) fix(sequentialagent): correct New godoc placement and copy-pasted error string (#1151) (David Mora, 2026-08-28)
- [996dafa](https://github.com/google/adk-go/commit/996dafaedf7037fb22d4a3f35d93a6ac6474615f) fix(loadartifactstool): support load_artifacts when combined with other tool calls (#1320) (Sarthak Chaudhari, 2026-08-28)
- [65fe522](https://github.com/google/adk-go/commit/65fe5224281fb30c9f2d2335beba9fe60fa5b196) test(artifact): cover version lookup after deletion (#681) (#1415) (mikemikimike, 2026-08-28)
- [d16048f](https://github.com/google/adk-go/commit/d16048f65888c47ee811ee69f912a29831f604e4) Adding opt-in option for the debug endpoint in ADK REST API (#1413) (Karol Droste, 2026-08-28)
- [f741f47](https://github.com/google/adk-go/commit/f741f478cfeb5ccecf4d6a0dedc70b18717648de) fix(agentanalytics): skip logging partial chunks in AfterModelCallback (#1214) (nuthalapativarun, 2026-08-28)
- [7e1f9f8](https://github.com/google/adk-go/commit/7e1f9f8f5f6f9d632fb6e0724bb781642c221267) fix(gcsartifact): recognize wrapped storage.ErrObjectNotExist (#1375) (Jeremy Schoemaker, 2026-08-28)
- [972f55f](https://github.com/google/adk-go/commit/972f55fd6aaaad56dcabcbe7d1ef4c7f0df5a632) fix(preloadmemorytool): guard against nil parts in extractText (#1349) (Sarthak Chaudhari, 2026-08-28)
- [e23ce16](https://github.com/google/adk-go/commit/e23ce16c19898897a741034055843313bfd4786e) docs: point AI coding agents at the hosted llms.txt (#1402) (wolo, 2026-08-28)
- [3774587](https://github.com/google/adk-go/commit/3774587df01c6af8d6dc7888e7b5695b83e9cfb5) tool/loadartifactstool: return error instead of panic when artifact service is not configured (#1390) (Gerard, 2026-08-28)
- [ef4f703](https://github.com/google/adk-go/commit/ef4f7030f0f6a9fd0bad4d4a6c05519abc5d8724) fix(examples): remove unused code in loadartifacts (#635) (Matheus Valiente Souza, 2026-08-28)
- [8a64214](https://github.com/google/adk-go/commit/8a64214dc6928d646840502de1248700363d5d72) docs: replace the nonexistent TempStatePrefix in state delta comments (#1311) (Trainingcqy, 2026-08-28)
- [f514a39](https://github.com/google/adk-go/commit/f514a39876fe28118385d9a99992443e9db35a95) skip scheduled nightly runs (#1366) (Suraj B, 2026-08-28)
- [3f69c50](https://github.com/google/adk-go/commit/3f69c5059e2adc6c127aa10d595b547e98f3da0c) fix(session/database): format stale-session timestamps as UnixMicro (#1237) (PratikDhanave, 2026-08-28)

## Changed Files

- `M	.github/workflows/nightly.yml`
- `M	README.md`
- `M	agent/common_context.go`
- `M	agent/workflowagents/sequentialagent/agent.go`
- `M	artifact/gcsartifact/gcs_test.go`
- `M	artifact/gcsartifact/service.go`
- `M	cmd/adkgo/internal/deploy/cloudrun/cloudrun.go`
- `M	cmd/launcher/web/api/api.go`
- `M	examples/tools/loadartifacts/main.go`
- `M	internal/artifact/tests/service_suite.go`
- `M	internal/sessionutils/utils.go`
- `M	plugin/agentanalytics/bigquery_agent_analytics_plugin.go`
- `M	plugin/agentanalytics/bigquery_agent_analytics_plugin_test.go`
- `M	server/adkrest/handler.go`
- `M	server/adkrest/handler_test.go`
- `M	session/database/service.go`
- `M	session/database/service_test.go`
- `M	tool/loadartifactstool/load_artifacts_tool.go`
- `M	tool/loadartifactstool/load_artifacts_tool_test.go`
- `M	tool/preloadmemorytool/tool.go`
- `M	tool/preloadmemorytool/tool_test.go`
