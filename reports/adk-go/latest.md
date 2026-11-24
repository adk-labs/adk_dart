# ADK Go Daily Change Report

- Date (UTC): 2026-11-24
- Source: `google/adk-go`
- Latest SHA: `57c6bd80dc6a981e2db426fecb33adc139e509ac`
- Previous SHA: `3f5d74d36e3f5c734904516bc83fd1b8556722dc`

## Summary

- New commits: 5

## Commits

- [57c6bd8](https://github.com/google/adk-go/commit/57c6bd80dc6a981e2db426fecb33adc139e509ac) fix(adkrest): reject runtime-only fields in create-session events (#1995) (João Westerberg, 2026-11-23)
- [8b338c2](https://github.com/google/adk-go/commit/8b338c2e7569be4d3a07f544efe0597cd6f43a59) fix(loadartifactstool): attach artifacts from every parallel call (#2417) (ktsoator, 2026-11-23)
- [366f608](https://github.com/google/adk-go/commit/366f608bfb7b88bd4eba232be0d87ee7c82c03c5) fix(preloadmemorytool): exclude thought parts from memory queries (#1852) (ktsoator, 2026-11-23)
- [f779980](https://github.com/google/adk-go/commit/f77998059feaaa053b64c3a650106067b452d162) fix(agentanalytics): require adk/v2 v2.8.0 and patched klauspost/compress (#2477) (Jan Wojtas, 2026-11-23)
- [a5af272](https://github.com/google/adk-go/commit/a5af27267d35cc97dda82de4d3ba50502533206d) chore(deps): bump the go-minor-patch group with 3 updates (#2469) (dependabot[bot], 2026-11-23)

## Changed Files

- `M	go.mod`
- `M	go.sum`
- `M	internal/llminternal/auth_preprocessor.go`
- `M	plugin/agentanalytics/go.mod`
- `M	plugin/agentanalytics/go.sum`
- `M	server/adkrest/controllers/sessions.go`
- `M	server/adkrest/controllers/sessions_test.go`
- `M	server/adkrest/sessions_integration_test.go`
- `M	tool/loadartifactstool/load_artifacts_tool.go`
- `M	tool/loadartifactstool/load_artifacts_tool_test.go`
- `M	tool/preloadmemorytool/tool.go`
- `M	tool/preloadmemorytool/tool_test.go`
