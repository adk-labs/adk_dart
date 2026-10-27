# ADK Go Daily Change Report

- Date (UTC): 2026-10-27
- Source: `google/adk-go`
- Latest SHA: `19707a2660a8dd7b8ffb32837027253ed2f29dd1`
- Previous SHA: `219c13059ecf654b7318d5927a607779711943e0`

## Summary

- New commits: 8

## Commits

- [19707a2](https://github.com/google/adk-go/commit/19707a2660a8dd7b8ffb32837027253ed2f29dd1) fix(ci): stop every CI run from building with an empty Go cache (#1972) (João Westerberg, 2026-10-27)
- [ab19ff2](https://github.com/google/adk-go/commit/ab19ff216ade4c4b00477d78c05d688f3229e204) fix(openaimodel): refuse config fields genai adds before they are supported (#1922) (Jan Wojtas, 2026-10-27)
- [e51f0ef](https://github.com/google/adk-go/commit/e51f0ef2d35c5f97d778ba51e95281e80db6f86a) fix(openaimodel): use adk_response when the schema title is not a valid format name (#1912) (Jan Wojtas, 2026-10-27)
- [8db87f4](https://github.com/google/adk-go/commit/8db87f44e47c9535b2600a9e866333ec6b94658f) fix(auth): keep the init context alive so token sources can refresh (#1904) (Jan Wojtas, 2026-10-27)
- [4152aea](https://github.com/google/adk-go/commit/4152aeab1740030a25ba012123266cf289855187) chore(deps): bump the go_modules group across 1 directory with 2 updates (#1934) (dependabot[bot], 2026-10-27)
- [751c5ec](https://github.com/google/adk-go/commit/751c5ec34f3bc0251b90d8f62d78d408afac57ce) fix(memory): skip thought parts in in-memory search and preloaded memories (#1975) (Gangavarapu Vivek, 2026-10-27)
- [231e007](https://github.com/google/adk-go/commit/231e0073ed157eb761c910fcda6f144ba097c095) fix(launcher): honor WithOtelToCloud in launcher.Config.TelemetryOptions (#1968) (Saurav Gupta, 2026-10-27)
- [1af51a3](https://github.com/google/adk-go/commit/1af51a3d869aacc215885c19f7ba95133446eb7c) fix(functiontool): preserve streaming consumer panics (#1961) (Jabrail, 2026-10-27)

## Changed Files

- `M	.github/actions/setup/action.yml`
- `M	.github/workflows/go.yml`
- `M	auth/providers.go`
- `M	auth/providers_internal_test.go`
- `M	cmd/launcher/console/console.go`
- `M	cmd/launcher/internal/telemetry/telemetry.go`
- `A	cmd/launcher/internal/telemetry/telemetry_test.go`
- `M	cmd/launcher/web/web.go`
- `M	memory/inmemory.go`
- `M	memory/inmemory_search_test.go`
- `M	model/openaimodel/doc.go`
- `M	model/openaimodel/internal/completions/request.go`
- `M	model/openaimodel/internal/completions/request_test.go`
- `M	model/openaimodel/internal/responses/request.go`
- `M	model/openaimodel/internal/responses/request_test.go`
- `M	model/openaimodel/internal/shared/config.go`
- `M	model/openaimodel/internal/shared/config_test.go`
- `M	model/openaimodel/internal/shared/schema.go`
- `M	model/openaimodel/internal/shared/schema_test.go`
- `M	plugin/agentanalytics/go.mod`
- `M	plugin/agentanalytics/go.sum`
- `M	tool/functiontool/streaming_function.go`
- `M	tool/functiontool/streaming_function_test.go`
- `M	tool/preloadmemorytool/tool.go`
- `M	tool/preloadmemorytool/tool_test.go`
