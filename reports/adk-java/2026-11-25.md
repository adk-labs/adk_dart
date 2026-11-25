# ADK Java Daily Change Report

- Date (UTC): 2026-11-25
- Source: `google/adk-java`
- Latest SHA: `38dadb1439558f817daf9daff3b1676aa3f808b2`
- Previous SHA: `b7dc20409fae459faf48e98eabf8f349e7597a6b`

## Summary

- New commits: 12

## Commits

- [38dadb14](https://github.com/google/adk-java/commit/38dadb1439558f817daf9daff3b1676aa3f808b2) fix(workflow): keep an agent passed to rootNode as the app's root node (Damian Momot, 2026-11-25)
- [99ca4f2d](https://github.com/google/adk-java/commit/99ca4f2da314ad4d92e5091831d7ac569de8450c) fix(workflow): align quoted enum handling across resume answers, parallel nodes and anyOf schemas (Mateusz Krawiec, 2026-11-25)
- [6ffa1f09](https://github.com/google/adk-java/commit/6ffa1f09fb3a31eeeb6dd3bcf0be369f8abbaef5) fix(models): run a repeated streamed function call once (Google Team Member, 2026-11-25)
- [53e15db9](https://github.com/google/adk-java/commit/53e15db903a0a10e9475ba1eb2cbca4037e4c029) feat(live): run before- and after-model callbacks in live runs (Damian Momot, 2026-11-25)
- [c736e2bd](https://github.com/google/adk-java/commit/c736e2bde1aa1656f8862021599426a1abf69ae9) fix(live): keep unsent requests queued and copy them only to running tools (Damian Momot, 2026-11-25)
- [d30bca47](https://github.com/google/adk-java/commit/d30bca47253f28e2dc864a221494bcea6f3e1d47) fix(models): fix how streamed function call chunks are assembled (Google Team Member, 2026-11-25)
- [baff0dd2](https://github.com/google/adk-java/commit/baff0dd2028a951d9e99d4d964886f0cd8f34ce8) fix(live): aggregate input and output transcriptions per utterance (Damian Momot, 2026-11-25)
- [a854669e](https://github.com/google/adk-java/commit/a854669e85e6630309d1944920d2af2c48896a1e) fix(live): close the connection when the model stream ends (Damian Momot, 2026-11-25)
- [1a5e8314](https://github.com/google/adk-java/commit/1a5e8314f443b7f011ed8c2610f22f78a8cdc85f) fix(workflow): read RequestInput answers as their response schema reads them (Mateusz Krawiec, 2026-11-25)
- [1bb1a7f8](https://github.com/google/adk-java/commit/1bb1a7f8a26e128f12ff87a7266a179ba60dbd40) docs(examples): accept user messages as String in first workflow nodes (Damian Momot, 2026-11-25)
- [a03b3bf4](https://github.com/google/adk-java/commit/a03b3bf41387d9272dee64c2ce0001dc7530f12e) fix(workflow): keep an agent node waiting on unanswered long-running calls (Damian Momot, 2026-11-25)
- [78500b7e](https://github.com/google/adk-java/commit/78500b7e546c7fa37f25138c30b4322f7cb96025) fix(runner): run plugin beforeRun, onEvent and afterRun callbacks in runLive (Damian Momot, 2026-11-25)

## Changed Files

- `M	core/src/main/java/com/google/adk/agents/ActiveStreamingTool.java`
- `M	core/src/main/java/com/google/adk/agents/Callbacks.java`
- `M	core/src/main/java/com/google/adk/agents/LiveRequestQueue.java`
- `M	core/src/main/java/com/google/adk/agents/NodeViewAgent.java`
- `M	core/src/main/java/com/google/adk/apps/App.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/BaseLlmFlow.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/Functions.java`
- `M	core/src/main/java/com/google/adk/models/Gemini.java`
- `M	core/src/main/java/com/google/adk/models/GeminiLlmConnection.java`
- `M	core/src/main/java/com/google/adk/models/StreamingResponseAggregator.java`
- `M	core/src/main/java/com/google/adk/runner/Runner.java`
- `M	core/src/main/java/com/google/adk/workflow/FunctionNodes.java`
- `M	core/src/main/java/com/google/adk/workflow/MessageReader.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `M	core/src/main/java/com/google/adk/workflow/ParallelWorkers.java`
- `M	core/src/main/java/com/google/adk/workflow/RequestInput.java`
- `M	core/src/main/java/com/google/adk/workflow/ResumeScan.java`
- `M	core/src/main/java/com/google/adk/workflow/Scheduler.java`
- `M	core/src/main/java/com/google/adk/workflow/SchemaFit.java`
- `M	core/src/main/java/com/google/adk/workflow/ToolConfirmations.java`
- `M	core/src/main/java/com/google/adk/workflow/ValueCoercer.java`
- `M	core/src/test/java/com/google/adk/agents/LiveRequestQueueTest.java`
- `M	core/src/test/java/com/google/adk/agents/NodeViewAgentTest.java`
- `M	core/src/test/java/com/google/adk/apps/AppTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/AgentTransferTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/BaseLlmFlowCancelTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/EndInvocationActionTest.java`
- `A	core/src/test/java/com/google/adk/flows/llmflows/LiveModelCallbacksTest.java`
- `M	core/src/test/java/com/google/adk/models/GeminiLlmConnectionTest.java`
- `M	core/src/test/java/com/google/adk/models/GeminiTest.java`
- `M	core/src/test/java/com/google/adk/models/StreamingResponseAggregatorTest.java`
- `M	core/src/test/java/com/google/adk/runner/RunnerTest.java`
- `M	core/src/test/java/com/google/adk/testing/TestLlm.java`
- `M	core/src/test/java/com/google/adk/tools/streaming/StreamingToolTest.java`
- `M	core/src/test/java/com/google/adk/workflow/FunctionNodeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/LlmAgentAsNodeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ParallelWorkersTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ResumeScanTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ToolNodesTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ValueCoercerTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowHitlTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowResumeTest.java`
- `M	examples/workflows/ClassifierNodeWorkflow.java`
- `M	examples/workflows/DynamicFanOutFanInWorkflow.java`
- `M	examples/workflows/DynamicNodesWorkflow.java`
- `M	examples/workflows/FanOutFanInWorkflow.java`
- `M	examples/workflows/LoopSelfWorkflow.java`
- `M	examples/workflows/LoopWorkflow.java`
- `M	examples/workflows/MultiTriggersWorkflow.java`
- `M	examples/workflows/NestedWorkflow.java`
- `M	examples/workflows/NodeOutputWorkflow.java`
- `M	examples/workflows/OrderProcessingWorkflow.java`
- `M	examples/workflows/ParallelWorkerWorkflow.java`
- `M	examples/workflows/RequestInputRerunWorkflow.java`
- `M	examples/workflows/RequestInputWorkflow.java`
- `M	examples/workflows/ResearchWorkflow.java`
- `M	examples/workflows/RouteWorkflow.java`
- `M	examples/workflows/StateWorkflow.java`
- `M	examples/workflows/SupportTriageWorkflow.java`
- `M	examples/workflows/UseAsOutputWorkflow.java`
