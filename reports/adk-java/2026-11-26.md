# ADK Java Daily Change Report

- Date (UTC): 2026-11-26
- Source: `google/adk-java`
- Latest SHA: `b51541a001fd97c084c12a971a7f9d05e272dfd3`
- Previous SHA: `38dadb1439558f817daf9daff3b1676aa3f808b2`

## Summary

- New commits: 16

## Commits

- [b51541a0](https://github.com/google/adk-java/commit/b51541a001fd97c084c12a971a7f9d05e272dfd3) feat(workflow): reject agent names that can't be node names when they run as nodes (Miłosz Sobczyk, 2026-11-26)
- [6f6204d7](https://github.com/google/adk-java/commit/6f6204d7dfb24c1ebdecceac6b6f4ea847efabe1) feat(workflow): resume paused peer and parent handoff targets (Miłosz Sobczyk, 2026-11-26)
- [f81468ce](https://github.com/google/adk-java/commit/f81468ceb0e60af7d1f3762fb568a993cefd3ad3) feat(workflow): follow parent and peer handoffs as workflow nodes (Miłosz Sobczyk, 2026-11-26)
- [9f0bdf75](https://github.com/google/adk-java/commit/9f0bdf7545ede2db8d2e27eee881f7b5407d29bf) feat(workflow): run a sub-agent handoff as its own workflow node (Miłosz Sobczyk, 2026-11-26)
- [71b7b758](https://github.com/google/adk-java/commit/71b7b758750f3415a339b932d6d77243b0082bb0) feat(workflow): start no other node while a task node waits (Miłosz Sobczyk, 2026-11-26)
- [75d8990e](https://github.com/google/adk-java/commit/75d8990e2578e294620805765ec3843b64a2b7b9) feat(workflow): continue a waiting task with the user's reply (Miłosz Sobczyk, 2026-11-26)
- [f94b028a](https://github.com/google/adk-java/commit/f94b028a74093091bd574da342fe3d1e491da3df) fix(workflow): resume agent nodes that pause after a sub-agent handoff (Damian Momot, 2026-11-26)
- [f1cc8891](https://github.com/google/adk-java/commit/f1cc889194448b21241e4b0bbcf39591ebb14019) fix(live): use dedicated audio and video fields for Gemini 3.x Live models (Damian Momot, 2026-11-26)
- [8aa71c07](https://github.com/google/adk-java/commit/8aa71c07b0558ad901db8a9fae83d7ccae79022b) Merge pull request #1882 from zhangxiangnan:fix/compaction-summary-validation (Copybara-Service, 2026-11-26)
- [f02b5d96](https://github.com/google/adk-java/commit/f02b5d96a8cff4d8ef96e05724044157e82adac3) test(workflow): test how a resumed answer reads a quoted string under string and anyOf schemas (Mateusz Krawiec, 2026-11-26)
- [5a0da749](https://github.com/google/adk-java/commit/5a0da74984822199434fc384e1c8932380d33a6b) fix(live): carry grounding metadata onto live responses (Damian Momot, 2026-11-26)
- [ebbbdc54](https://github.com/google/adk-java/commit/ebbbdc542bb65b75aaac38060246139a20bf62b7) fix(live): pass built-in tools and safety settings to live connections (Damian Momot, 2026-11-26)
- [5f3f5996](https://github.com/google/adk-java/commit/5f3f5996e54520c93ea5b94816222066982c0e3a) fix(models): keep a streamed function call where it started (Google Team Member, 2026-11-26)
- [e97c0b41](https://github.com/google/adk-java/commit/e97c0b41e3b159b30bf9fe46b97403492ccbd8df) feat(workflow): check FunctionNode builder schemas and dynamic child input (Mateusz Krawiec, 2026-11-26)
- [bb8d31a7](https://github.com/google/adk-java/commit/bb8d31a7f2b8ca2eaf16d5b42c88ccd37434bb4d) feat(workflow): check node input and output against their schemas at run time (Mateusz Krawiec, 2026-11-26)
- [6c3381fc](https://github.com/google/adk-java/commit/6c3381fc5000609deda747f59af32d99087db4de) fix(summarizer): skip compaction when the summary is unusable (zhangxiangnan, 2026-11-23)

## Changed Files

- `M	core/src/main/java/com/google/adk/SchemaUtils.java`
- `M	core/src/main/java/com/google/adk/agents/AgentMode.java`
- `M	core/src/main/java/com/google/adk/agents/BaseAgent.java`
- `M	core/src/main/java/com/google/adk/agents/Context.java`
- `M	core/src/main/java/com/google/adk/agents/LlmAgent.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/BaseLlmFlow.java`
- `M	core/src/main/java/com/google/adk/models/Gemini.java`
- `M	core/src/main/java/com/google/adk/models/GeminiLlmConnection.java`
- `M	core/src/main/java/com/google/adk/models/StreamingResponseAggregator.java`
- `M	core/src/main/java/com/google/adk/runner/Runner.java`
- `M	core/src/main/java/com/google/adk/summarizer/LlmEventSummarizer.java`
- `M	core/src/main/java/com/google/adk/workflow/BaseNode.java`
- `M	core/src/main/java/com/google/adk/workflow/FunctionNode.java`
- `M	core/src/main/java/com/google/adk/workflow/GraphValidation.java`
- `M	core/src/main/java/com/google/adk/workflow/JoinNode.java`
- `M	core/src/main/java/com/google/adk/workflow/Node.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeExecutionState.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeNames.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `M	core/src/main/java/com/google/adk/workflow/ParallelWorkers.java`
- `M	core/src/main/java/com/google/adk/workflow/ResumeScan.java`
- `M	core/src/main/java/com/google/adk/workflow/Scheduler.java`
- `A	core/src/main/java/com/google/adk/workflow/TransferTarget.java`
- `M	core/src/main/java/com/google/adk/workflow/Workflow.java`
- `M	core/src/test/java/com/google/adk/SchemaUtilsTest.java`
- `M	core/src/test/java/com/google/adk/models/GeminiLlmConnectionTest.java`
- `M	core/src/test/java/com/google/adk/models/GeminiTest.java`
- `M	core/src/test/java/com/google/adk/models/StreamingResponseAggregatorTest.java`
- `A	core/src/test/java/com/google/adk/summarizer/CompactionSummaryValidationTest.java`
- `A	core/src/test/java/com/google/adk/workflow/AgentTransferLoopTest.java`
- `M	core/src/test/java/com/google/adk/workflow/BaseNodeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/FunctionNodeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/LlmAgentAsNodeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/LlmAgentModeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/LlmAgentTaskModeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/NodeExecutionStateTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ParallelWorkersTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ResumeScanTest.java`
- `A	core/src/test/java/com/google/adk/workflow/TaskContinuationTest.java`
- `M	core/src/test/java/com/google/adk/workflow/TaskDelegationTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowHitlTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowResumeTesting.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowTest.java`
