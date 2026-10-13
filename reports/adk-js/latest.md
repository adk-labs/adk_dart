# ADK JS Daily Change Report

- Date (UTC): 2026-10-13
- Source: `google/adk-js`
- Latest SHA: `ad0540e65706bc6593798bcfce35298448747df7`
- Previous SHA: `14c9c3d58b915dc834306f851bb25c71d3f243c5`

## Summary

- New commits: 14

## Commits

- [ad0540e](https://github.com/google/adk-js/commit/ad0540e65706bc6593798bcfce35298448747df7) Release: v2.3.0 (#975) (Alexey Kalenkevich, 2026-10-13)
- [31a56e8](https://github.com/google/adk-js/commit/31a56e8eded2f7ab5b09c4f3d9548f2e710f41eb) feat(agents): port agents features from adk-python (#1070) (adk-foundry-bot, 2026-10-13)
- [146a4df](https://github.com/google/adk-js/commit/146a4df22377dd509cf310f81388b793be52f02b) test(sessions): remove the dead nodejs-vertexai mock from VertexAiSessionService tests (#1020) (adk-foundry-bot, 2026-10-13)
- [966d49c](https://github.com/google/adk-js/commit/966d49c7eb072611fc49766d09355a11823680d9) fix(core): end call_llm span in finally when runAsync exits early (#1068) (hirematha, 2026-10-14)
- [bda36c1](https://github.com/google/adk-js/commit/bda36c1c131bc084c01057d41111a3203d3c324a) refactor(models): drop Gemini continuation handling now done by @google/genai (#1050) (Alexey Kalenkevich, 2026-10-13)
- [245ba2e](https://github.com/google/adk-js/commit/245ba2e2931153ca85d71e84cf5b406c0182efd1) fix(sessions): follow nextPageToken when listing events in VertexAiSessionService.getSession (#1029) (#1043) (Varun-S10, 2026-10-13)
- [5e7af7e](https://github.com/google/adk-js/commit/5e7af7e767f29c13de30320403fe84b26b163a94) fix(core): set llmRequest.model to selected route model in RoutedLlm (#1062) (Varun-S10, 2026-10-13)
- [f42e5c2](https://github.com/google/adk-js/commit/f42e5c29cda850063e0f7cab4abbb688d5fe7c8d) fix(core): stop parent step loop after transfer_to_agent in SSE mode (#1063) (Varun-S10, 2026-10-13)
- [43ba911](https://github.com/google/adk-js/commit/43ba9117415806ef85767f07b635c2839b9f9c42) fix(core): normalize tool responses before afterToolCallback runs (#1035) (#1061) (Varun-S10, 2026-10-13)
- [8efe0fe](https://github.com/google/adk-js/commit/8efe0fe60e1c743aed929b96aec9953f784a1ae1) fix(models): forward abortSignal in RoutedLlm.generateContentAsync (#1038) (#1064) (Varun-S10, 2026-10-13)
- [3700444](https://github.com/google/adk-js/commit/370044469b74497885403fc690e3943a9ab163ae) fix(core): persist sandbox name in _code_execution_context state delta (#1039) (#1065) (Varun-S10, 2026-10-13)
- [67ea8a6](https://github.com/google/adk-js/commit/67ea8a6e99ce7e79d6a567c2895734f30ce6025e) fix(core): prefer explicit appName over app.name in Runner (#1040) (#1066) (Varun-S10, 2026-10-13)
- [47fadc9](https://github.com/google/adk-js/commit/47fadc9ab1855ea03bc2ef75d8295d3fa4a03da8) fix(core): use ^1.9.0 range for @opentelemetry/api (#1041) (#1067) (Varun-S10, 2026-10-13)
- [5e31749](https://github.com/google/adk-js/commit/5e317493a1b7291920b03daa3b0a33a7a10e401e) fix(core): keep one event id across partial chunks of a streamed response (#1042) (#1069) (Varun-S10, 2026-10-13)

## Changed Files

- `M	.release-please-manifest.json`
- `M	core/CHANGELOG.md`
- `M	core/package.json`
- `M	core/src/agents/functions.ts`
- `M	core/src/agents/invocation_context.ts`
- `A	core/src/agents/langgraph_agent.ts`
- `M	core/src/agents/llm_agent.ts`
- `A	core/src/agents/remote_agent.ts`
- `M	core/src/code_executors/agent_engine_sandbox_code_executor.ts`
- `M	core/src/code_executors/code_executor_context.ts`
- `M	core/src/common.ts`
- `M	core/src/context/summarizers/llm_summarizer.ts`
- `M	core/src/context/token_based_context_compactor.ts`
- `M	core/src/events/event.ts`
- `D	core/src/models/gemini_continuation.ts`
- `M	core/src/models/google_llm.ts`
- `M	core/src/models/llm_response.ts`
- `M	core/src/models/routed_llm.ts`
- `M	core/src/runner/in_memory_runner.ts`
- `M	core/src/runner/runner.ts`
- `M	core/src/sessions/vertex_ai_session_service.ts`
- `M	core/src/utils/streaming_utils.ts`
- `M	core/src/version.ts`
- `M	core/test/agents/functions_test.ts`
- `M	core/test/agents/invocation_context_test.ts`
- `A	core/test/agents/langgraph_agent_test.ts`
- `M	core/test/agents/llm_agent_live_telemetry_test.ts`
- `M	core/test/agents/llm_agent_test.ts`
- `A	core/test/agents/remote_agent_test.ts`
- `M	core/test/code_executors/agent_engine_sandbox_code_executor_test.ts`
- `M	core/test/context/anchored_context_compactor_test.ts`
- `M	core/test/context/summarizers/llm_summarizer_test.ts`
- `M	core/test/context/token_based_context_compactor_test.ts`
- `D	core/test/models/gemini_continuation_test.ts`
- `M	core/test/models/llm_response_test.ts`
- `M	core/test/models/routed_llm_test.ts`
- `M	core/test/package_install_weight_test.ts`
- `M	core/test/runner/in_memory_runner_test.ts`
- `M	core/test/runner/runner_test.ts`
- `M	core/test/sessions/vertex_ai_session_service_test.ts`
- `M	dev/CHANGELOG.md`
- `M	dev/package.json`
- `M	dev/src/version.ts`
- `M	dev/test/server/adk_api_server_test.ts`
- `M	docs/guides/README.md`
- `A	docs/guides/agents/index.md`
- `M	integrations/CHANGELOG.md`
- `M	integrations/package.json`
- `M	integrations/src/version.ts`
- `M	package-lock.json`
- `M	package.json`
- `A	samples/agents/README.md`
- `A	samples/agents/agent.ts`
- `D	tests/integration/models/gemini_continuation/gemini_continuation_test.ts`
