# ADK Java Daily Change Report

- Date (UTC): 2026-10-20
- Source: `google/adk-java`
- Latest SHA: `833cbd5751f615ecc162ef99a6c380f97c7d9144`
- Previous SHA: `dc56f11f0ebfca75f0024dde29daddf25b914f15`

## Summary

- New commits: 5

## Commits

- [833cbd57](https://github.com/google/adk-java/commit/833cbd5751f615ecc162ef99a6c380f97c7d9144) Merge pull request #1381 from YuqiGuo105:fix/issue-1200-live-turn-complete (Copybara-Service, 2026-10-20)
- [13b10bb5](https://github.com/google/adk-java/commit/13b10bb54dcbed52f0c11ac99defe6b2766e0e54) chore: send ADK tracking headers from Claude and from Apigee custom headers (Damian Momot, 2026-10-20)
- [48e9ae7a](https://github.com/google/adk-java/commit/48e9ae7a6f32ed678404a5cafc9b5f48118b0adb) chore: send one ADK tag and one Java tag on every Gemini request (Damian Momot, 2026-10-20)
- [28f2606c](https://github.com/google/adk-java/commit/28f2606ce05d20444bb0c5e8db37d98ec1727b59) feat: run a single workflow node (Damian Momot, 2026-10-19)
- [857ee63a](https://github.com/google/adk-java/commit/857ee63ada5cf6bcd10dcab7259949a76d1f00f2) feat: expose turnComplete for live content (YuqiGuo105, 2026-10-19)

## Changed Files

- `M	core/pom.xml`
- `M	core/src/main/java/com/google/adk/agents/BaseAgent.java`
- `M	core/src/main/java/com/google/adk/agents/Context.java`
- `M	core/src/main/java/com/google/adk/agents/LiveRequest.java`
- `M	core/src/main/java/com/google/adk/agents/LiveRequestQueue.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/BaseLlmFlow.java`
- `M	core/src/main/java/com/google/adk/models/ApigeeLlm.java`
- `M	core/src/main/java/com/google/adk/models/BaseLlmConnection.java`
- `M	core/src/main/java/com/google/adk/models/Claude.java`
- `M	core/src/main/java/com/google/adk/models/Gemini.java`
- `M	core/src/main/java/com/google/adk/models/GeminiLlmConnection.java`
- `A	core/src/main/java/com/google/adk/models/TrackingHeaders.java`
- `A	core/src/main/java/com/google/adk/workflow/NodeExecutionState.java`
- `A	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `M	core/src/test/java/com/google/adk/agents/BaseAgentTest.java`
- `M	core/src/test/java/com/google/adk/agents/ContextTest.java`
- `A	core/src/test/java/com/google/adk/agents/LiveRequestQueueTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/BaseLlmFlowTest.java`
- `M	core/src/test/java/com/google/adk/models/ApigeeLlmTest.java`
- `A	core/src/test/java/com/google/adk/models/BaseLlmConnectionTest.java`
- `M	core/src/test/java/com/google/adk/models/ClaudeTest.java`
- `M	core/src/test/java/com/google/adk/models/GeminiLlmConnectionTest.java`
- `A	core/src/test/java/com/google/adk/models/GeminiTrackingHeadersTest.java`
- `A	core/src/test/java/com/google/adk/models/TrackingHeadersTest.java`
- `M	core/src/test/java/com/google/adk/testing/TestLlm.java`
- `R059	core/src/test/java/com/google/adk/workflow/StubNode.java	core/src/test/java/com/google/adk/testing/TestNode.java`
- `M	core/src/test/java/com/google/adk/workflow/EdgeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/EdgesBuilderTest.java`
- `M	core/src/test/java/com/google/adk/workflow/GraphTest.java`
- `A	core/src/test/java/com/google/adk/workflow/NodeExecutionStateTest.java`
- `A	core/src/test/java/com/google/adk/workflow/NodeRunnerTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowTest.java`
