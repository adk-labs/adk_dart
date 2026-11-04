# ADK Go Daily Change Report

- Date (UTC): 2026-11-04
- Source: `google/adk-go`
- Latest SHA: `0c109f7dad33815bcee4f101b7b724a1293d8823`
- Previous SHA: `fe992528e7d1c7e9f648158d47957c241c569ff3`

## Summary

- New commits: 9

## Commits

- [0c109f7](https://github.com/google/adk-go/commit/0c109f7dad33815bcee4f101b7b724a1293d8823) fix(session/vertexai): drop temp: keys from the initial state on Create (#2100) (Aditya Singh, 2026-11-04)
- [074b087](https://github.com/google/adk-go/commit/074b087948ec7f8d4f6a9708b0c84c3a4981b8c8) fix(llminternal): end the turn when a preprocessed tool response is final (#2104) (Aditya Singh, 2026-11-04)
- [dbaca47](https://github.com/google/adk-go/commit/dbaca475d108ac5da198b7fa80fce8b8aa7dd294) fix(runner): run OnEvent and AfterRun for a BeforeRun reply in RunLive (#2105) (Aditya Singh, 2026-11-04)
- [f6da03a](https://github.com/google/adk-go/commit/f6da03ab78210ab24f4a63c192a37dfe385b2694) fix(adkrest): let AutoCreateSession reach /run and /run_sse (#2106) (Aditya Singh, 2026-11-04)
- [1c35470](https://github.com/google/adk-go/commit/1c3547019cb4d661ce5f4b3cbff8af65e11eb6bb) fix(adka2a): keep LLM agent instructions out of agent card skills (#2110) (Aditya Singh, 2026-11-04)
- [826b5e2](https://github.com/google/adk-go/commit/826b5e2cef1b0aaa1e915034ceb2fc0aa2765b45) chore(main): release 2.7.1 (#2136) (ADK Go Bot, 2026-11-04)
- [569e96d](https://github.com/google/adk-go/commit/569e96d1366a59f67dc82e6d267e34e4aa08b2a3) test(artifact): cover loading a nonexistent version in the shared service suite (#2131) (adk-foundry-bot, 2026-11-04)
- [bb1fd51](https://github.com/google/adk-go/commit/bb1fd51a68a220d994103a8f86620544d52ed2ed) ci: run the release job in the release-please environment (#2135) (Jan Wojtas, 2026-11-04)
- [2b507a6](https://github.com/google/adk-go/commit/2b507a6f1612379e90df8d7ffd7f3189c43eca81) ci: set the release-please baseline to v2.7.0 (#2134) (Jan Wojtas, 2026-11-04)

## Changed Files

- `M	.github/.release-please-manifest.json`
- `M	.github/release-please-config.json`
- `M	.github/workflows/release.yml`
- `A	CHANGELOG.md`
- `M	internal/artifact/tests/service_suite.go`
- `M	internal/llminternal/base_flow.go`
- `M	internal/llminternal/parallel_function_call_hitl_test.go`
- `M	internal/version/version.go`
- `M	runner/live_runner_test.go`
- `M	runner/runner.go`
- `M	server/adka2a/v2/agent_card.go`
- `M	server/adka2a/v2/agent_card_test.go`
- `M	server/adkrest/controllers/runtime.go`
- `M	server/adkrest/controllers/runtime_test.go`
- `M	session/vertexai/append_event_temp_state_test.go`
- `M	session/vertexai/vertexai_client.go`
