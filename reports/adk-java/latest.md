# ADK Java Daily Change Report

- Date (UTC): 2026-10-13
- Source: `google/adk-java`
- Latest SHA: `5137604e2a8f9ddacced43b0cbd918f26ac1f2ed`
- Previous SHA: `dbc973bfcfc1b23ca04fed3cf8f8bb84f03ab160`

## Summary

- New commits: 9

## Commits

- [5137604e](https://github.com/google/adk-java/commit/5137604e2a8f9ddacced43b0cbd918f26ac1f2ed) feat: add the experimental JoinNode workflow node (Damian Momot, 2026-10-13)
- [91a18386](https://github.com/google/adk-java/commit/91a183865e5e14499e827961cb96df24a0476ea1) feat: add a context caching demo sample (Kamil Tomaszek, 2026-10-13)
- [68914c59](https://github.com/google/adk-java/commit/68914c59e254e50fece01711d5213d3c03b07090) fix: create and use Gemini context caches when ContextCacheConfig is set (Kamil Tomaszek, 2026-10-13)
- [4c77cdfa](https://github.com/google/adk-java/commit/4c77cdface117da17f79778e5a5726db1fdefc99) feat: add the experimental Workflow type for workflow graphs (Damian Momot, 2026-10-13)
- [a7b317a8](https://github.com/google/adk-java/commit/a7b317a8dc8d19bc406de63e556ece3fdf2c5f80) feat: add the experimental Edge and Start workflow types (Damian Momot, 2026-10-13)
- [e5083e3b](https://github.com/google/adk-java/commit/e5083e3ba9410ec32eb8d785d0f1f31eed7375d4) feat: add a Gemini context cache manager (Kamil Tomaszek, 2026-10-13)
- [6ea7b84d](https://github.com/google/adk-java/commit/6ea7b84d960cb4323bbde0080b5e2717eb51bc67) test: add a fake Gemini API for context cache tests (Kamil Tomaszek, 2026-10-13)
- [187a4e12](https://github.com/google/adk-java/commit/187a4e1234a8d949c6b33b201a9a6b39e995f21a) feat: carry context cache config and metadata on LlmRequest, LlmResponse and Event (Kamil Tomaszek, 2026-10-13)
- [3afe4e5e](https://github.com/google/adk-java/commit/3afe4e5e12800f604c83365383c808a4760f736c) feat: add cacheIntervals and createHttpOptions to ContextCacheConfig, as in ADK Python (Kamil Tomaszek, 2026-10-13)

## Changed Files

- `M	core/src/main/java/com/google/adk/agents/ContextCacheConfig.java`
- `M	core/src/main/java/com/google/adk/events/Event.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/BaseLlmFlow.java`
- `A	core/src/main/java/com/google/adk/flows/llmflows/ContextCacheRequestProcessor.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/SingleFlow.java`
- `A	core/src/main/java/com/google/adk/models/CacheMetadata.java`
- `M	core/src/main/java/com/google/adk/models/Gemini.java`
- `A	core/src/main/java/com/google/adk/models/GeminiContextCacheManager.java`
- `M	core/src/main/java/com/google/adk/models/LlmRequest.java`
- `M	core/src/main/java/com/google/adk/models/LlmResponse.java`
- `A	core/src/main/java/com/google/adk/workflow/Edge.java`
- `A	core/src/main/java/com/google/adk/workflow/Graph.java`
- `A	core/src/main/java/com/google/adk/workflow/JoinNode.java`
- `A	core/src/main/java/com/google/adk/workflow/Start.java`
- `A	core/src/main/java/com/google/adk/workflow/Workflow.java`
- `A	core/src/test/java/com/google/adk/agents/ContextCacheConfigTest.java`
- `M	core/src/test/java/com/google/adk/events/EventTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/BaseLlmFlowTest.java`
- `A	core/src/test/java/com/google/adk/flows/llmflows/ContextCacheRequestProcessorTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/SingleFlowTest.java`
- `A	core/src/test/java/com/google/adk/models/CacheMetadataTest.java`
- `A	core/src/test/java/com/google/adk/models/FakeGeminiApi.java`
- `A	core/src/test/java/com/google/adk/models/FakeGeminiApiTest.java`
- `A	core/src/test/java/com/google/adk/models/GeminiContextCacheManagerTest.java`
- `A	core/src/test/java/com/google/adk/models/GeminiContextCachingTest.java`
- `M	core/src/test/java/com/google/adk/models/LlmRequestTest.java`
- `M	core/src/test/java/com/google/adk/models/LlmResponseTest.java`
- `A	core/src/test/java/com/google/adk/workflow/EdgeTest.java`
- `A	core/src/test/java/com/google/adk/workflow/GraphTest.java`
- `A	core/src/test/java/com/google/adk/workflow/JoinNodeTest.java`
- `A	core/src/test/java/com/google/adk/workflow/StartTest.java`
- `A	core/src/test/java/com/google/adk/workflow/StubNode.java`
- `A	core/src/test/java/com/google/adk/workflow/WorkflowTest.java`
- `M	examples/README.md`
- `A	examples/contextcaching/ContextCachingAgent.java`
- `A	examples/contextcaching/ContextCachingRun.java`
- `A	examples/contextcaching/README.md`
- `A	examples/contextcaching/pom.xml`
- `M	examples/pom.xml`
