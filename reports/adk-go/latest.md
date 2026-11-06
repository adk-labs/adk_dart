# ADK Go Daily Change Report

- Date (UTC): 2026-11-06
- Source: `google/adk-go`
- Latest SHA: `dd8330ffd3c0d08bcd56f56eb8569762995de2c8`
- Previous SHA: `d0c978b0ce4fe2068be977eb5fd90a0add2dd462`

## Summary

- New commits: 22

## Commits

- [dd8330f](https://github.com/google/adk-go/commit/dd8330ffd3c0d08bcd56f56eb8569762995de2c8) docs: explain how a merged commit links an issue in the release notes (#2141) (Jan Wojtas, 2026-11-06)
- [869020a](https://github.com/google/adk-go/commit/869020a1c3ba754790513f0371544e603ea3e238) fix(agentregistry): speak A2A 0.3 to 0.3 interfaces (#2145) (wolo, 2026-11-06)
- [dc44b8c](https://github.com/google/adk-go/commit/dc44b8c96d3c54b613e06f1f746b920500d363ef) fix(workflow): return ctx.Err() instead of a partial ParallelWorker result (#2146) (Jan Wojtas, 2026-11-06)
- [c7087e3](https://github.com/google/adk-go/commit/c7087e3e44b23e3adeb2bbe1911ef57e239983cd) feat(cli): configure Agent Engine deployment environment (#1981) (Jabrail, 2026-11-06)
- [ca21a26](https://github.com/google/adk-go/commit/ca21a26fb0021c922a4489e22ba7b380299ae64e) perf(llminternal): use strings.Builder in streaming response aggregator (#2051) (Sega, 2026-11-06)
- [010b91e](https://github.com/google/adk-go/commit/010b91e9807ad6c5c8f73da84c0187a50fde0164) fix(workflow): honor UUID provider for tool node call IDs (#2030) (Francesc Campoy, 2026-11-06)
- [8be9129](https://github.com/google/adk-go/commit/8be9129edf02611366a8c58344046bba5ab25437) fix(llminternal): keep ModelVersion on the aggregated streaming response (#2070) (Aditya Singh, 2026-11-06)
- [8ce8f01](https://github.com/google/adk-go/commit/8ce8f01ca5a628aa6e37cc4cd7c0525b92f7177f) fix(adkrest): answer 500, not 404, when /run cannot read the session (#2107) (Aditya Singh, 2026-11-06)
- [249974d](https://github.com/google/adk-go/commit/249974dc15580f08d11629581641ad45a47f646e) feat(authhandler): add the server side of the end-user OAuth2 consent flow (#2143) (Sasha, 2026-11-06)
- [82b64f4](https://github.com/google/adk-go/commit/82b64f452060f3bdd0f6034521d4fa82a503f6fe) fix(sequentialagent): stop RunLive on a sub-agent error, as Run does (#2151) (Prathmesh, 2026-11-06)
- [ded357e](https://github.com/google/adk-go/commit/ded357e351dee44c023398a49d314aa326a59c94) fix(openaimodel): send executable code parts as text (#1956) (Mangesh Raut, 2026-11-06)
- [de7088b](https://github.com/google/adk-go/commit/de7088bf4aa5c9445adbc4e8b362c5c1927dde95) fix(runner): treat the inbound message as a user turn (#1877) (Anzal Husain Abidi, 2026-11-06)
- [9f7f1d4](https://github.com/google/adk-go/commit/9f7f1d49d306f1eb7df920285d21d0beeaa92813) chore(model/openaimodel): update media conversion tests and comments (#1888) (ktsoator, 2026-11-06)
- [27c1cc5](https://github.com/google/adk-go/commit/27c1cc5d5e3f32a7d7a925b39024243b2cbe3c58) test(gemini): add unit test for maybeAppendUserContent (#2155) (adk-foundry-bot, 2026-11-05)
- [217c3b0](https://github.com/google/adk-go/commit/217c3b0d54f6cb5aac9b8bec7f3907f158be622e) ci: require a conventional-commit subject on pull requests (#1487) (Jan Wojtas, 2026-11-06)
- [123fea9](https://github.com/google/adk-go/commit/123fea94f49d7387c915602e4386a1b7ecd27aca) fix(triggers): use timer-and-select for context-aware retry backoff (#2052) (Sega, 2026-11-06)
- [7af0f5f](https://github.com/google/adk-go/commit/7af0f5f06a545df1d59d0ee4e0c59063689dee9d) fix(session/database): delete a session's events explicitly in Delete (#1774) (Davide Imola, 2026-11-05)
- [8360e75](https://github.com/google/adk-go/commit/8360e75d5c4bdd8dbf587f12c057a292f8270d3e) feat(mcptoolset): add tool name prefixes (#1821) (ktsoator, 2026-11-06)
- [c377836](https://github.com/google/adk-go/commit/c377836c419a1d1a17e9b054c9aad34de68cf2a7) fix(adkrest): preserve debug span attribute types (#1988) (ktsoator, 2026-11-06)
- [275e190](https://github.com/google/adk-go/commit/275e190e8c501b83dce6d77c22f69341cda44aa9) fix(openaimodel): refuse non-function Tool fields genai adds (#1983) (Mangesh Raut, 2026-11-06)
- [7c87fdf](https://github.com/google/adk-go/commit/7c87fdff09af9311e05d488190dedc1aaaa7bc30) fix(remoteagent): resume tasks with mixed tool responses (#2148) (Chen Yufeiyang, 2026-11-06)
- [a3ecc67](https://github.com/google/adk-go/commit/a3ecc670bfa2b786e6455742fda50dbc17e9358c) ci: release plugin/agentanalytics with release-please (#2147) (Jan Wojtas, 2026-11-05)

## Changed Files

- `M	.github/.release-please-manifest.json`
- `M	.github/release-please-config.json`
- `A	.github/scripts/check-conventional-subject.sh`
- `A	.github/workflows/require-conventional-subject.yml`
- `M	AGENTS.md`
- `M	CONTRIBUTING.md`
- `M	agent/remoteagent/v2/a2a_e2e_test.go`
- `M	agent/remoteagent/v2/utils.go`
- `M	agent/remoteagent/v2/utils_test.go`
- `M	agent/workflowagents/sequentialagent/agent.go`
- `M	agent/workflowagents/sequentialagent/agent_test.go`
- `M	agentregistry/factory.go`
- `M	agentregistry/factory_test.go`
- `M	agentregistry/remoteagent_e2e_test.go`
- `M	cmd/adkgo/internal/deploy/agentengine/agentengine.go`
- `A	cmd/adkgo/internal/deploy/agentengine/environment.go`
- `A	cmd/adkgo/internal/deploy/agentengine/environment_test.go`
- `A	internal/authhandler/authuri.go`
- `A	internal/authhandler/authuri_test.go`
- `A	internal/authhandler/exchange.go`
- `A	internal/authhandler/exchange_internal_test.go`
- `A	internal/authhandler/request.go`
- `A	internal/authhandler/request_test.go`
- `A	internal/authhandler/response.go`
- `A	internal/authhandler/response_internal_test.go`
- `A	internal/authhandler/store.go`
- `A	internal/authhandler/store_internal_test.go`
- `A	internal/authhandler/store_test.go`
- `M	internal/llminternal/parallel_function_call_test.go`
- `M	internal/llminternal/stream_aggregator.go`
- `M	internal/llminternal/stream_aggregator_test.go`
- `M	model/gemini/gemini_test.go`
- `M	model/openaimodel/internal/completions/media_test.go`
- `M	model/openaimodel/internal/completions/request.go`
- `M	model/openaimodel/internal/completions/request_test.go`
- `M	model/openaimodel/internal/responses/request.go`
- `M	model/openaimodel/internal/responses/request_test.go`
- `M	model/openaimodel/internal/shared/contents.go`
- `M	model/openaimodel/internal/shared/contents_test.go`
- `M	model/openaimodel/internal/shared/errors.go`
- `M	model/openaimodel/internal/shared/media.go`
- `M	model/openaimodel/internal/shared/tools.go`
- `M	model/openaimodel/internal/shared/tools_test.go`
- `M	runner/runner.go`
- `M	runner/runner_test.go`
- `M	server/adkrest/controllers/debug.go`
- `M	server/adkrest/controllers/debug_test.go`
- `M	server/adkrest/controllers/errors.go`
- `M	server/adkrest/controllers/handlers.go`
- `M	server/adkrest/controllers/runtime.go`
- `M	server/adkrest/controllers/runtime_test.go`
- `M	server/adkrest/controllers/triggers/pubsub_test.go`
- `M	server/adkrest/controllers/triggers/triggers.go`
- `M	server/adkrest/internal/services/debugtelemetry.go`
- `M	server/adkrest/internal/services/debugtelemetry_test.go`
- `M	session/database/service.go`
- `M	session/database/service_test.go`
- `A	tool/mcptoolset/prefix_test.go`
- `M	tool/mcptoolset/set.go`
- `M	tool/mcptoolset/tool.go`
- `M	tool/mcptoolset/tool_test.go`
- `M	workflow/parallel_worker.go`
- `M	workflow/parallel_worker_test.go`
- `M	workflow/tool_node.go`
- `M	workflow/tool_node_test.go`
