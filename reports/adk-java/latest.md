# ADK Java Daily Change Report

- Date (UTC): 2026-10-23
- Source: `google/adk-java`
- Latest SHA: `84bae34a9ae4c133c7e6294faff5cb50f64a3474`
- Previous SHA: `17687a92fba166ad7911766e3e59689b23d19a51`

## Summary

- New commits: 14

## Commits

- [84bae34a](https://github.com/google/adk-java/commit/84bae34a9ae4c133c7e6294faff5cb50f64a3474) revert: restrict turn-based `transfer_to_agent` to declared targets (Mateusz Krawiec, 2026-10-23)
- [18554a19](https://github.com/google/adk-java/commit/18554a19295b603d4c6140bd790486b96c7c1bc1) revert: restrict live `transfer_to_agent` to the agent, its sub-agents, parent, and peers (Mateusz Krawiec, 2026-10-23)
- [85780688](https://github.com/google/adk-java/commit/85780688fb0c1cb02f8c89a4fcbd6ec7dc0eba03) feat: pause a workflow for user input (Damian Momot, 2026-10-23)
- [a313ce4a](https://github.com/google/adk-java/commit/a313ce4af4844ae36ecfbd17db3d38fc16345723) feat: share one run per Context.runNode run ID (Damian Momot, 2026-10-23)
- [2e88a6de](https://github.com/google/adk-java/commit/2e88a6de4c9735f104986d34a4d461a6a36e06be) feat: resume a paused workflow from its session events (Damian Momot, 2026-10-23)
- [b0bdd989](https://github.com/google/adk-java/commit/b0bdd989b77548aa480029310cb15b5e1e3bc019) Merge pull request #1442 from pgentile:rag_retrieval_similarity_top_k (Copybara-Service, 2026-10-23)
- [7096019e](https://github.com/google/adk-java/commit/7096019e4581da5899d5b41e6bdd8ba3c847db75) feat: rebuild a workflow's node progress from session events (Damian Momot, 2026-10-23)
- [41aa2506](https://github.com/google/adk-java/commit/41aa2506fed26f8f4240e6cc9e6459a8f0f69546) Merge pull request #1570 from Laurianti:fix-loop-agent-non-positive-max-iterations (Copybara-Service, 2026-10-23)
- [9a158552](https://github.com/google/adk-java/commit/9a158552079bdba10f6d59a39d7c4bc62dbde485) fix(live): replay stored transcriptions as conversation history (Kamil Tomaszek, 2026-10-22)
- [f4d6de4c](https://github.com/google/adk-java/commit/f4d6de4cc2e4d6765449753e1a3ddf94c579a7db) fix: restrict live `transfer_to_agent` to the agent, its sub-agents, parent, and peers (Kamil Tomaszek, 2026-10-22)
- [c781145c](https://github.com/google/adk-java/commit/c781145c79a9ddad56eadb9ef8b61644c37b1518) Merge pull request #1589 from quifox:fix/skill-resource-mixed-parts (Copybara-Service, 2026-10-22)
- [71bd1cdc](https://github.com/google/adk-java/commit/71bd1cdcacf28b58a2e0682f2dbf7c757392bc91) feat: configure similarity top-K in the VertexAiRagRetrieval tool (Pierre Gentile, 2026-08-19)
- [e1fbed9f](https://github.com/google/adk-java/commit/e1fbed9f52275e817a1a1c3b55a7c15128e7377e) fix(skills): preserve sibling parts when loading binary resources (quifox, 2026-10-01)
- [5feaae49](https://github.com/google/adk-java/commit/5feaae492a3b22f0a1813575f19d4bef3db101bd) fix(agents): run LoopAgent zero times when maxIterations is zero or negative (Laurianti, 2026-10-01)

## Changed Files

- `M	core/pom.xml`
- `M	core/src/main/java/com/google/adk/agents/Context.java`
- `M	core/src/main/java/com/google/adk/agents/LlmAgent.java`
- `M	core/src/main/java/com/google/adk/agents/LoopAgent.java`
- `D	core/src/main/java/com/google/adk/agents/TransferRejectedException.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/BaseLlmFlow.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/Contents.java`
- `M	core/src/main/java/com/google/adk/runner/Runner.java`
- `M	core/src/main/java/com/google/adk/tools/retrieval/VertexAiRagRetrieval.java`
- `M	core/src/main/java/com/google/adk/tools/skills/LoadSkillResourceTool.java`
- `M	core/src/main/java/com/google/adk/workflow/BaseNode.java`
- `M	core/src/main/java/com/google/adk/workflow/Node.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeExecutionState.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeState.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeStatus.java`
- `A	core/src/main/java/com/google/adk/workflow/RequestInput.java`
- `A	core/src/main/java/com/google/adk/workflow/ResumeScan.java`
- `M	core/src/main/java/com/google/adk/workflow/RunNodeConfig.java`
- `M	core/src/main/java/com/google/adk/workflow/Scheduler.java`
- `M	core/src/test/java/com/google/adk/agents/LlmAgentTest.java`
- `M	core/src/test/java/com/google/adk/agents/LoopAgentTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/AgentTransferTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/ContentsTest.java`
- `M	core/src/test/java/com/google/adk/runner/RunnerRootNodeTest.java`
- `M	core/src/test/java/com/google/adk/runner/RunnerTest.java`
- `M	core/src/test/java/com/google/adk/tools/retrieval/VertexAiRagRetrievalTest.java`
- `A	core/src/test/java/com/google/adk/tools/skills/LoadSkillResourceMixedPartsRegressionTest.java`
- `A	core/src/test/java/com/google/adk/workflow/ResumeScanTest.java`
- `A	core/src/test/java/com/google/adk/workflow/WorkflowHitlTest.java`
- `A	core/src/test/java/com/google/adk/workflow/WorkflowResumeTest.java`
- `A	core/src/test/java/com/google/adk/workflow/WorkflowResumeTesting.java`
