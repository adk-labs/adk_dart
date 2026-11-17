# ADK Go Daily Change Report

- Date (UTC): 2026-11-17
- Source: `google/adk-go`
- Latest SHA: `012af4d94fb0ad67713180a4233d63c5fd520d1c`
- Previous SHA: `02b1d0b5c73633f620653efb1e51beb9d48d1d74`

## Summary

- New commits: 10

## Commits

- [012af4d](https://github.com/google/adk-go/commit/012af4d94fb0ad67713180a4233d63c5fd520d1c) feat(tool/skilltoolset/skill/gcsskill): add Cloud Storage skill source (#2384) (Artsiom Shut, 2026-11-17)
- [b289e33](https://github.com/google/adk-go/commit/b289e334241085f59f76b096e8f0682f16f6e76b) feat(vertexairagtool): expose RAG retrieval configuration (#2324) (Deepak DHAKAD, 2026-11-17)
- [cf55159](https://github.com/google/adk-go/commit/cf55159d2d7894e682fb006267910a8ded36ccb6) fix(agentanalytics): redact and bound code part labels in summaries (#2332) (Raunak Burrows, 2026-11-17)
- [aacc2fa](https://github.com/google/adk-go/commit/aacc2fa46f06651dcf561eed94123f9d460a96dd) fix(telemetry): leave no span processor running when New fails (#2318) (argaj, 2026-11-17)
- [534f30b](https://github.com/google/adk-go/commit/534f30b654787ac6fff386adac223be83c686eca) fix(llminternal): accept Unicode identifier characters in instruction state names (#2334) (0z5a, 2026-11-17)
- [e374e9e](https://github.com/google/adk-go/commit/e374e9e5f4468adcbd3804a24f967fa4b4a498a8) fix(runner): skip nil parts in response events and input blob extraction (#2322) (Harsh Arora, 2026-11-17)
- [b388580](https://github.com/google/adk-go/commit/b388580ea8fd9562c8311a64bb7a61c8f67bcb85) fix(loggingplugin): truncate text by character, not byte (#2342) (Muhammad Abdullah Butt, 2026-11-17)
- [f887982](https://github.com/google/adk-go/commit/f8879822a83fdbe07ef323e7d6eeb1de0f31637d) fix(session): apply persistent changes only after database commit (#2305) (ktsoator, 2026-11-17)
- [ca197aa](https://github.com/google/adk-go/commit/ca197aaaa582e9c6d85da4559729a099a7c98907) fix(agentanalytics): preserve retired late parent cancel cause and custom metadata truncation flag (#2020) (Haiyuan Cao, 2026-11-17)
- [126ad4e](https://github.com/google/adk-go/commit/126ad4e816ca9ef1b6deb53adb766f30cb7c6303) fix(live): send tracking headers on live connections (#2369) (jWos1, 2026-11-17)

## Changed Files

- `M	agent/llmagent/llmagent.go`
- `M	examples/tools/vertexairagtool/main.go`
- `M	exp/vertexairagtool/vertexairag.go`
- `M	exp/vertexairagtool/vertexairag_test.go`
- `M	internal/llminternal/instruction_processor.go`
- `M	internal/llminternal/instruction_processor_test.go`
- `M	internal/version/tracking.go`
- `M	internal/version/tracking_test.go`
- `M	model/gemini/gemini.go`
- `M	model/gemini/gemini_test.go`
- `M	plugin/agentanalytics/bigquery_agent_analytics_plugin.go`
- `M	plugin/agentanalytics/doc.go`
- `M	plugin/agentanalytics/events.go`
- `M	plugin/agentanalytics/events_test.go`
- `M	plugin/agentanalytics/json_formatter.go`
- `M	plugin/agentanalytics/json_formatter_test.go`
- `M	plugin/agentanalytics/trace_manager.go`
- `M	plugin/agentanalytics/trace_manager_test.go`
- `M	plugin/loggingplugin/logging_plugin.go`
- `A	plugin/loggingplugin/logging_plugin_test.go`
- `M	runner/live_runner_test.go`
- `M	runner/runner.go`
- `M	runner/runner_test.go`
- `M	session/database/service.go`
- `M	session/database/service_test.go`
- `M	session/database/session.go`
- `M	session/inmemory.go`
- `M	telemetry/setup_otel.go`
- `M	telemetry/telemetry_test.go`
- `M	tool/mcptoolset/tracking.go`
- `M	tool/mcptoolset/tracking_test.go`
- `A	tool/skilltoolset/skill/gcsskill/fake_gcs_test.go`
- `A	tool/skilltoolset/skill/gcsskill/source.go`
- `A	tool/skilltoolset/skill/gcsskill/source_test.go`
- `M	util/instructionutil/instruction.go`
