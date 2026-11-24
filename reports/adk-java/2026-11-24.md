# ADK Java Daily Change Report

- Date (UTC): 2026-11-24
- Source: `google/adk-java`
- Latest SHA: `b7dc20409fae459faf48e98eabf8f349e7597a6b`
- Previous SHA: `548d0a13bb4fd103da2a766dfb801355fc6bfcd2`

## Summary

- New commits: 13

## Commits

- [b7dc2040](https://github.com/google/adk-java/commit/b7dc20409fae459faf48e98eabf8f349e7597a6b) fix(workflow): fail an agent node when a confirmed tool fails (Damian Momot, 2026-11-24)
- [67bd999e](https://github.com/google/adk-java/commit/67bd999e5bcb0948ceffee20d74bf9769df2739c) fix(live): keep the live call up when a tool sets endOfAgent (Damian Momot, 2026-11-24)
- [2fb48418](https://github.com/google/adk-java/commit/2fb484187b23c20061670db5fc40200dc9902909) feat(live): end a SequentialAgent step when the model calls task_completed (Damian Momot, 2026-11-24)
- [aed10b49](https://github.com/google/adk-java/commit/aed10b49543ae342bbd9eee1fa86a16526c82f47) Merge pull request #1719 from pinqionghongbai:fix/a2a-context-id-session (Copybara-Service, 2026-11-24)
- [2e5859d7](https://github.com/google/adk-java/commit/2e5859d735e73853f093745b65766c108b6fbee6) fix(workflow): end an agent node's turn when a FunctionTool requests confirmation (Damian Momot, 2026-11-24)
- [d9095f54](https://github.com/google/adk-java/commit/d9095f54d9c123370c34f310033709536ba338a1) fix(models): build one final streamed response from the whole stream (Google Team Member, 2026-11-24)
- [c817b1f7](https://github.com/google/adk-java/commit/c817b1f76c9c029d9c097e25212b3b3e3fcb7ec7) fix(dev): find tool-response traces by event id (Damian Osadczuk, 2026-11-24)
- [9c752850](https://github.com/google/adk-java/commit/9c7528506aafd96dabf015228b3f8d611a7bec56) Merge pull request #1653 from innoprej:fix/firestore-event-order (Copybara-Service, 2026-11-24)
- [3c689700](https://github.com/google/adk-java/commit/3c6897006c71306ee71252328a63ff7ec5ad580e) refactor(models): move Gemini stream aggregation into StreamingResponseAggregator (Google Team Member, 2026-11-24)
- [523e6d3c](https://github.com/google/adk-java/commit/523e6d3cf9f466ba886580112acf0a5cfa592131) fix(flows): pass ReadonlyContext when resolving tools on confirmation resume (Google Team Member, 2026-11-24)
- [22928911](https://github.com/google/adk-java/commit/229289117c9cf2789497e237201db05510ab13c8) fix(live): send each tool result once after an agent transfer (Damian Momot, 2026-11-24)
- [983317ae](https://github.com/google/adk-java/commit/983317ae77a3c97051eb5dd2d114af81262fb06f) fix(a2a): create the session under the A2A context id (hongbailingmeng, 2026-11-08)
- [1a6dd29e](https://github.com/google/adk-java/commit/1a6dd29e41c6f21f81b8fbef051a330afd2da6e3) fix: keep Firestore session events in time order (Jaehee Shin, 2026-10-12)

## Changed Files

- `M	a2a/src/main/java/com/google/adk/a2a/executor/AgentExecutor.java`
- `M	a2a/src/test/java/com/google/adk/a2a/executor/AgentExecutorTest.java`
- `M	contrib/firestore-session-service/src/main/java/com/google/adk/sessions/FirestoreSessionService.java`
- `M	contrib/firestore-session-service/src/test/java/com/google/adk/sessions/FirestoreSessionServiceTest.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/BaseLlmFlow.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/RequestConfirmationLlmRequestProcessor.java`
- `A	core/src/main/java/com/google/adk/flows/llmflows/TaskCompletedTool.java`
- `M	core/src/main/java/com/google/adk/models/Gemini.java`
- `A	core/src/main/java/com/google/adk/models/StreamingResponseAggregator.java`
- `M	core/src/main/java/com/google/adk/tools/FunctionTool.java`
- `M	core/src/test/java/com/google/adk/agents/SequentialAgentTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/AgentTransferTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/BaseLlmFlowCancelTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/EndInvocationActionTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/RequestConfirmationLlmRequestProcessorTest.java`
- `M	core/src/test/java/com/google/adk/models/GeminiTest.java`
- `A	core/src/test/java/com/google/adk/models/StreamingResponseAggregatorTest.java`
- `M	core/src/test/java/com/google/adk/runner/RunnerResumabilityTest.java`
- `M	core/src/test/java/com/google/adk/workflow/LlmAgentAsNodeTest.java`
- `M	dev/src/main/java/com/google/adk/web/service/ApiServerSpanExporter.java`
- `M	dev/src/test/java/com/google/adk/web/service/ApiServerSpanExporterTest.java`
