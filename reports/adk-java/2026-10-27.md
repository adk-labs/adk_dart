# ADK Java Daily Change Report

- Date (UTC): 2026-10-27
- Source: `google/adk-java`
- Latest SHA: `461f7d6fd9d7fc1ee99e7bf3a788040810caf7d3`
- Previous SHA: `2c84291bc6601dbe61bbbba5a34743f356e65403`

## Summary

- New commits: 12

## Commits

- [461f7d6f](https://github.com/google/adk-java/commit/461f7d6fd9d7fc1ee99e7bf3a788040810caf7d3) fix: close the Gemini response stream after a read error (Google Team Member, 2026-10-27)
- [367b402d](https://github.com/google/adk-java/commit/367b402db39f93ab430f473f48bce89a301bbb60) fix: enforce node retry policies and timeouts (Damian Momot, 2026-10-27)
- [08ca7012](https://github.com/google/adk-java/commit/08ca70123d3ade0bb4ce008439bd122b911eddd6) test: cover inline data metadata on session reloads (Google Team Member, 2026-10-27)
- [9949265e](https://github.com/google/adk-java/commit/9949265e6ca09ecfab888b608572a47b962db37f) feat: add bidirectional conversion between ADK and Spring AI (Rafal Glowinski, 2026-10-27)
- [1917ec14](https://github.com/google/adk-java/commit/1917ec145bd42cc6bb91374f2375b81c6ff03624) Merge pull request #1607 from hermanrous:fix/sessions-inline-data-mimetype (Copybara-Service, 2026-10-27)
- [087614ce](https://github.com/google/adk-java/commit/087614ceaf8f8576e9b0d8adb534f630300d3389) Merge pull request #1643 from innoprej:fix/firestore-session-whole-events (Copybara-Service, 2026-10-27)
- [7ed0a93d](https://github.com/google/adk-java/commit/7ed0a93d591dd0533f0ada90ce03a3a44579a9a5) Merge pull request #1621 from sangkyoonnam:fix/1618-cancel-propagation (Copybara-Service, 2026-10-27)
- [1a18907d](https://github.com/google/adk-java/commit/1a18907d9d93cca71bb0aa1e832b54c0efa89a05) Merge pull request #1412 from svetanis:feature/save-files-as-artifacts-plugin (Copybara-Service, 2026-10-27)
- [272ea6cb](https://github.com/google/adk-java/commit/272ea6cbcc8f61311e810e79d23d7f08dad31563) feat(plugins): port SaveFilesAsArtifactsPlugin from adk-python (svetanis, 2026-08-07)
- [cce02ae7](https://github.com/google/adk-java/commit/cce02ae7914b289b81aae8128d1b3cebaad65786) fix(flows): propagate downstream cancellation to the model stream (Sangkyoon Nam, 2026-10-06)
- [a1610094](https://github.com/google/adk-java/commit/a1610094728b67abac7ed77833d086bb5cad45ea) fix: stop losing event fields on Firestore session reloads (Jaehee Shin, 2026-10-10)
- [f7af931a](https://github.com/google/adk-java/commit/f7af931a8da97a4c2357ec6d14d66fec5f739f2f) fix(sessions): keep inlineData mimeType when encoding or decoding content (Chengmian Liu, 2026-10-04)

## Changed Files

- `M	contrib/firestore-session-service/src/main/java/com/google/adk/sessions/FirestoreSessionService.java`
- `M	contrib/firestore-session-service/src/test/java/com/google/adk/sessions/FirestoreSessionServiceTest.java`
- `M	contrib/spring-ai/src/main/java/com/google/adk/models/springai/ConfigMapper.java`
- `M	contrib/spring-ai/src/main/java/com/google/adk/models/springai/EmbeddingConverter.java`
- `M	contrib/spring-ai/src/main/java/com/google/adk/models/springai/MessageConverter.java`
- `A	contrib/spring-ai/src/main/java/com/google/adk/models/springai/SpringAiTool.java`
- `A	contrib/spring-ai/src/main/java/com/google/adk/models/springai/SpringAiToolset.java`
- `M	contrib/spring-ai/src/main/java/com/google/adk/models/springai/ToolConverter.java`
- `M	contrib/spring-ai/src/test/java/com/google/adk/models/springai/ConfigMapperTest.java`
- `M	contrib/spring-ai/src/test/java/com/google/adk/models/springai/MessageConverterTest.java`
- `A	contrib/spring-ai/src/test/java/com/google/adk/models/springai/SpringAiToolTest.java`
- `A	contrib/spring-ai/src/test/java/com/google/adk/models/springai/SpringAiToolsetTest.java`
- `M	contrib/spring-ai/src/test/java/com/google/adk/models/springai/ToolConverterTest.java`
- `M	contrib/spring-ai/src/test/java/com/google/adk/models/springai/embeddings/EmbeddingConverterTest.java`
- `M	core/src/main/java/com/google/adk/agents/BaseAgent.java`
- `M	core/src/main/java/com/google/adk/agents/Context.java`
- `M	core/src/main/java/com/google/adk/agents/InvocationContext.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/BaseLlmFlow.java`
- `M	core/src/main/java/com/google/adk/models/Gemini.java`
- `A	core/src/main/java/com/google/adk/plugins/SaveFilesAsArtifactsPlugin.java`
- `M	core/src/main/java/com/google/adk/runner/Runner.java`
- `M	core/src/main/java/com/google/adk/sessions/SessionUtils.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeConfig.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeExecutionState.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `M	core/src/main/java/com/google/adk/workflow/ResumeScan.java`
- `M	core/src/main/java/com/google/adk/workflow/RetryConfig.java`
- `M	core/src/main/java/com/google/adk/workflow/Scheduler.java`
- `M	core/src/test/java/com/google/adk/agents/BaseAgentTest.java`
- `M	core/src/test/java/com/google/adk/agents/ContextTest.java`
- `A	core/src/test/java/com/google/adk/flows/llmflows/BaseLlmFlowCancelTest.java`
- `M	core/src/test/java/com/google/adk/models/GeminiContinuationTest.java`
- `M	core/src/test/java/com/google/adk/models/GeminiTest.java`
- `A	core/src/test/java/com/google/adk/plugins/SaveFilesAsArtifactsPluginTest.java`
- `M	core/src/test/java/com/google/adk/sessions/SessionJsonConverterTest.java`
- `A	core/src/test/java/com/google/adk/sessions/SessionUtilsTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ResumeScanTest.java`
- `M	core/src/test/java/com/google/adk/workflow/RetryConfigTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowResumeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowResumeTesting.java`
- `A	core/src/test/java/com/google/adk/workflow/WorkflowRetryTest.java`
