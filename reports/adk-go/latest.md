# ADK Go Daily Change Report

- Date (UTC): 2026-11-24
- Source: `google/adk-go`
- Latest SHA: `e52983b4b9d29d873e061e52e10ff391135feced`
- Previous SHA: `57c6bd80dc6a981e2db426fecb33adc139e509ac`

## Summary

- New commits: 5

## Commits

- [e52983b](https://github.com/google/adk-go/commit/e52983b4b9d29d873e061e52e10ff391135feced) fix(workflow): preserve array order in schema literal values (#2465) (噜噜, 2026-11-25)
- [29465f6](https://github.com/google/adk-go/commit/29465f6d392a6775079447b66f0c11cc03f890a6) feat(model/gemini): trace context cache actions and failures (#2419) (wolo, 2026-11-24)
- [ed17582](https://github.com/google/adk-go/commit/ed1758224eea3315507619446f3fc79e6d5ac25a) fix(anthropic): update default model configuration (#2486) (indurireddy-TF, 2026-11-24)
- [fea9549](https://github.com/google/adk-go/commit/fea95495a9f55d13536e03e0230f247c63e10adb) feat(adkrest): list artifact versions over REST (#2473) (ktsoator, 2026-11-24)
- [754138b](https://github.com/google/adk-go/commit/754138be96daa9a6d51d6e152e99ba56c889f7cf) fix(agentregistry): authenticate MCP egress only to Google API hosts (#2476) (wolo, 2026-11-24)

## Changed Files

- `M	agentregistry/factory.go`
- `M	agentregistry/factory_test.go`
- `M	examples/anthropic/README.md`
- `M	examples/anthropic/main.go`
- `M	examples/contextcache/README.md`
- `A	internal/telemetry/context_cache.go`
- `M	internal/utils/schema_canonical.go`
- `M	internal/utils/schema_canonical_test.go`
- `M	model/anthropicmodel/doc.go`
- `M	model/cache.go`
- `M	model/gemini/context_cache.go`
- `A	model/gemini/context_cache_telemetry_test.go`
- `M	model/gemini/context_cache_test.go`
- `M	model/gemini/gemini.go`
- `A	runner/context_cache_telemetry_test.go`
- `M	runner/context_cache_test.go`
- `A	server/adkrest/artifact_versions_integration_test.go`
- `M	server/adkrest/controllers/artifacts.go`
- `M	server/adkrest/controllers/artifacts_test.go`
- `M	server/adkrest/internal/routers/artifacts.go`
- `M	workflow/validation_test.go`
