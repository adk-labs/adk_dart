# ADK Java Daily Change Report

- Date (UTC): 2026-11-27
- Source: `google/adk-java`
- Latest SHA: `aa183f8b80f4bf19c7e3cc66061d5cede6674251`
- Previous SHA: `b51541a001fd97c084c12a971a7f9d05e272dfd3`

## Summary

- New commits: 12

## Commits

- [aa183f8b](https://github.com/google/adk-java/commit/aa183f8b80f4bf19c7e3cc66061d5cede6674251) fix(runner): route beforeRun early-exit events through onEvent callbacks and persist them (Mateusz Krawiec, 2026-11-27)
- [77b32c3c](https://github.com/google/adk-java/commit/77b32c3c92c0ad2a7c30c3e973bebb1fc876e2cf) fix(sessions): let callers ignore State.compute and merge results (Mateusz Krawiec, 2026-11-27)
- [e0d6c2ae](https://github.com/google/adk-java/commit/e0d6c2ae78e1de11b005920b51d38f5bc38caec1) feat(workflow): check a FunctionNode body's emitted state against the state schema (Mateusz Krawiec, 2026-11-27)
- [13cc9234](https://github.com/google/adk-java/commit/13cc92340d9bd47fb64ac552cded68f8d9c6fb20) feat(workflow): check node Context.state() writes against the state schema (Mateusz Krawiec, 2026-11-27)
- [a04a4007](https://github.com/google/adk-java/commit/a04a400765e160f9d0eb2a89dac63ad800d5ae62) feat(workflow): check a workflow's output against its output schema (Mateusz Krawiec, 2026-11-27)
- [006e5d5f](https://github.com/google/adk-java/commit/006e5d5fbd223635b434aa29b8578afbce3c2f7a) feat(workflow): check emitted event and tool node state deltas against stateSchema (Mateusz Krawiec, 2026-11-27)
- [0fd72013](https://github.com/google/adk-java/commit/0fd7201392d53de1f3f1b1fba894416c81f7bb13) fix(workflow): unify node schema checks and fix messages in maps (Mateusz Krawiec, 2026-11-27)
- [1cb0c807](https://github.com/google/adk-java/commit/1cb0c807bc3a696c33271d949ea93b340c923799) Merge pull request #1884 from zhangxiangnan:fix/mcp-null-arguments (Copybara-Service, 2026-11-27)
- [8e612c67](https://github.com/google/adk-java/commit/8e612c67f08bb302f911d94127d14ae5b41db54c) fix(live): save user content sent during a live run to the session (Damian Momot, 2026-11-27)
- [1868cd91](https://github.com/google/adk-java/commit/1868cd917932593dafc9966bab06a98ae66bc0fe) refactor(dev): share request validation between /run and /run_sse (Mateusz Krawiec, 2026-11-27)
- [6a98dc67](https://github.com/google/adk-java/commit/6a98dc67b14b4547b686c3213ba8ba96b87c9409) docs(examples): add samples that run task agents (Damian Momot, 2026-11-26)
- [562e43dc](https://github.com/google/adk-java/commit/562e43dcdb1060af0ac428d6fb518ed29afb8e97) fix: preserve explicit null arguments in MCP tools (zhangxiangnan, 2026-11-23)

## Changed Files

- `M	core/src/main/java/com/google/adk/agents/CallbackContext.java`
- `M	core/src/main/java/com/google/adk/agents/Context.java`
- `M	core/src/main/java/com/google/adk/agents/LlmAgent.java`
- `M	core/src/main/java/com/google/adk/classifiers/ClassifierNode.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/BaseLlmFlow.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/PersistBarrier.java`
- `M	core/src/main/java/com/google/adk/runner/Runner.java`
- `M	core/src/main/java/com/google/adk/sessions/State.java`
- `A	core/src/main/java/com/google/adk/sessions/StateSchemaException.java`
- `M	core/src/main/java/com/google/adk/tools/FunctionTool.java`
- `M	core/src/main/java/com/google/adk/tools/ToolContext.java`
- `M	core/src/main/java/com/google/adk/tools/mcp/McpAsyncTool.java`
- `M	core/src/main/java/com/google/adk/tools/mcp/McpTool.java`
- `M	core/src/main/java/com/google/adk/workflow/BaseNode.java`
- `M	core/src/main/java/com/google/adk/workflow/FunctionNode.java`
- `M	core/src/main/java/com/google/adk/workflow/Node.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeExecutionState.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `M	core/src/main/java/com/google/adk/workflow/PortCodec.java`
- `M	core/src/main/java/com/google/adk/workflow/Scheduler.java`
- `A	core/src/main/java/com/google/adk/workflow/SchemaValues.java`
- `M	core/src/main/java/com/google/adk/workflow/ToolNodes.java`
- `M	core/src/main/java/com/google/adk/workflow/Workflow.java`
- `M	core/src/test/java/com/google/adk/classifiers/ClassifierNodeTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/AgentTransferTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/LiveModelCallbacksTest.java`
- `M	core/src/test/java/com/google/adk/runner/RunnerTest.java`
- `M	core/src/test/java/com/google/adk/sessions/StateTest.java`
- `M	core/src/test/java/com/google/adk/tools/FunctionToolTest.java`
- `M	core/src/test/java/com/google/adk/tools/mcp/AbstractMcpToolTest.java`
- `M	core/src/test/java/com/google/adk/workflow/FunctionNodeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/LlmAgentTaskModeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/SchedulerTest.java`
- `A	core/src/test/java/com/google/adk/workflow/SchemaValuesTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ToolNodesTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowResumeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowResumeTesting.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowTest.java`
- `M	dev/src/main/java/com/google/adk/web/controller/ExecutionController.java`
- `A	dev/src/test/java/com/google/adk/web/controller/ExecutionControllerTest.java`
- `A	examples/workflows/AgentInWorkflow.java`
- `M	examples/workflows/README.md`
- `A	examples/workflows/TaskSubAgentDemo.java`
