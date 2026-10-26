# ADK Java Daily Change Report

- Date (UTC): 2026-10-26
- Source: `google/adk-java`
- Latest SHA: `2c84291bc6601dbe61bbbba5a34743f356e65403`
- Previous SHA: `84bae34a9ae4c133c7e6294faff5cb50f64a3474`

## Summary

- New commits: 9

## Commits

- [2c84291b](https://github.com/google/adk-java/commit/2c84291bc6601dbe61bbbba5a34743f356e65403) fix: keep context cache metadata in events and model responses (Damian Momot, 2026-10-26)
- [beca7764](https://github.com/google/adk-java/commit/beca7764d0e87c65267fa31b02b31e5d87f35ce3) fix: store grounded events in an adapted Java session service (Damian Momot, 2026-10-26)
- [dcbdf96c](https://github.com/google/adk-java/commit/dcbdf96caeb4cb059a84215bb0bc926f0e456d1c) test: stop sending the OpenAI key to the demo proxy in integration tests (Damian Osadczuk, 2026-10-26)
- [5177269f](https://github.com/google/adk-java/commit/5177269f54fd8ed7d42df9891ae5f8982f4e02b7) fix: drop a delegating node's own output, as Python ADK does (Damian Momot, 2026-10-26)
- [eb622e63](https://github.com/google/adk-java/commit/eb622e63b566eefdb03d6f9b30d74ff7120224ce) test: gate LocalModelIntegrationTest on ADK_RUN_LOCAL_MODEL_TESTS (Damian Osadczuk, 2026-10-26)
- [49e6c18d](https://github.com/google/adk-java/commit/49e6c18dc7d52e27b0ee998757f005832d0953e2) Merge pull request #1590 from quifox:fix/skill-tool-instruction (Copybara-Service, 2026-10-26)
- [86f31308](https://github.com/google/adk-java/commit/86f31308c96c41b15db63f870a12f05319c3ef55) feat: add Event.isolationScope (Damian Momot, 2026-10-26)
- [3e330b82](https://github.com/google/adk-java/commit/3e330b82f63a1d2fef196e84c958f5aaf8f15bc5) test: run the Gemini integration test against Vertex AI (Rafal Glowinski, 2026-10-26)
- [9d680532](https://github.com/google/adk-java/commit/9d680532a3dd3e4a67d18c81f5795225e432f1dd) fix(skills): remove unregistered script tool from default instructions (quifox, 2026-10-01)

## Changed Files

- `M	contrib/langchain4j/src/test/java/com/google/adk/models/langchain4j/LangChain4jIntegrationTest.java`
- `M	contrib/spring-ai/README.md`
- `M	contrib/spring-ai/src/test/java/com/google/adk/models/springai/integrations/GeminiApiIntegrationTest.java`
- `M	contrib/spring-ai/src/test/java/com/google/adk/models/springai/ollama/LocalModelIntegrationTest.java`
- `M	core/src/main/java/com/google/adk/events/Event.java`
- `M	core/src/main/java/com/google/adk/tools/skills/SkillToolset.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeExecutionState.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `M	core/src/main/java/com/google/adk/workflow/RunNodeConfig.java`
- `M	core/src/test/java/com/google/adk/events/EventTest.java`
- `M	core/src/test/java/com/google/adk/tools/skills/SkillToolsetTest.java`
- `M	core/src/test/java/com/google/adk/workflow/DynamicDispatchTest.java`
- `M	core/src/test/java/com/google/adk/workflow/DynamicWorkflowTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowResumeTest.java`
- `A	tokt/src/main/kotlin/com/google/adk/tokt/codecs/CacheMetadataCodec.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/EventCodec.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/GroundingMetadataCodec.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/LlmResponseCodec.kt`
- `M	tokt/src/test/kotlin/com/google/adk/tokt/KtRunnerInteropTest.kt`
