# ADK Java Daily Change Report

- Date (UTC): 2026-11-17
- Source: `google/adk-java`
- Latest SHA: `659f5abd897259f4e08c46c6418f267767127ab1`
- Previous SHA: `ef1335e8ea4b3618b2adb66b3e01e2caff23ec99`

## Summary

- New commits: 21

## Commits

- [659f5abd](https://github.com/google/adk-java/commit/659f5abd897259f4e08c46c6418f267767127ab1) fix(a2a): read the error code ADK Python and Go agents send (Google Team Member, 2026-11-17)
- [61ce0226](https://github.com/google/adk-java/commit/61ce0226e4fab89a0a930af2d4cb63f68a1ce6bf) feat(workflow): let a FunctionNode body ask for input with requestInput (Mateusz Krawiec, 2026-11-17)
- [f20d158a](https://github.com/google/adk-java/commit/f20d158a3b1425b8ff52ca5c99303cfcbbcceaa8) docs(workflow): show how a FunctionNode body composes child nodes (Mateusz Krawiec, 2026-11-17)
- [5aa6b5a4](https://github.com/google/adk-java/commit/5aa6b5a4d6b59b17eb4a94ea750d44af738f88fa) test(workflow): cover ctx.emit from helper threads, tools, timeouts and nested runs (Mateusz Krawiec, 2026-11-17)
- [f9ec28c0](https://github.com/google/adk-java/commit/f9ec28c0cbfdbd9496126b105f7f64c36f9eaeff) fix(flows): share the persist barrier with copies of callbackContextData (Damian Osadczuk, 2026-11-17)
- [c90ac7cc](https://github.com/google/adk-java/commit/c90ac7cc84af93ac14bed7f43e6d6d5d2c103e7e) feat(workflow): let a FunctionNode body send events with ctx.emit (Mateusz Krawiec, 2026-11-17)
- [d0c33381](https://github.com/google/adk-java/commit/d0c3338122c1e31df2c99d31e2180dd19a2c4a03) feat(workflow): run a FunctionNode body on the node's scheduler (Mateusz Krawiec, 2026-11-17)
- [6973a794](https://github.com/google/adk-java/commit/6973a794b8c931ed1db7a061e53fb64e107efb77) fix: wrap non-object output schemas for set_model_response (Mateusz Krawiec, 2026-11-17)
- [ba91fb83](https://github.com/google/adk-java/commit/ba91fb83adfb166b61681e4e9c236cd071ac2256) fix(workflow): run forked graph nodes concurrently when they block their threads (Damian Momot, 2026-11-17)
- [5ade8570](https://github.com/google/adk-java/commit/5ade8570fe8a8d572686bb8dc484978b583219e9) fix(a2a): continue the remote context on the next turn (Google Team Member, 2026-11-17)
- [7c80a146](https://github.com/google/adk-java/commit/7c80a1468015e770ac431c30f8ce2909d4e19a3d) fix(a2a): resume a remote agent's task when the user answers its call (Google Team Member, 2026-11-17)
- [1f7efe32](https://github.com/google/adk-java/commit/1f7efe3232d1dbecde771b936d43c9debc236de4) fix: keep apigee/gemini/ models on the Gemini API even when the environment selects Vertex AI (Mateusz Krawiec, 2026-11-17)
- [beda447a](https://github.com/google/adk-java/commit/beda447ae05cb18ec17ec85a8cbf564d8fa8ab60) feat(workflow): check an untyped enum on an edge as the number or boolean it spells (Mateusz Krawiec, 2026-11-17)
- [c5c238d0](https://github.com/google/adk-java/commit/c5c238d03b2c7f17e2a9ca00500557a093158d7d) fix(workflow): keep the caller's trace context in a FunctionNode body (Mateusz Krawiec, 2026-11-17)
- [efedf4c1](https://github.com/google/adk-java/commit/efedf4c10a065c37d4e843a82c462d68ffc34a7f) fix(a2a): keep the metadata of a message reply (Google Team Member, 2026-11-17)
- [ea207422](https://github.com/google/adk-java/commit/ea207422ac05016112162409a214ff0fa3f2799c) fix(workflow): keep a node timeout from interrupting a FunctionNode's output (Mateusz Krawiec, 2026-11-17)
- [59b4d1a1](https://github.com/google/adk-java/commit/59b4d1a17934d1f748ea3cc14cf3d370c918c5c4) docs(examples): add samples that run agents from a node and in parallel (Damian Momot, 2026-11-17)
- [7957d950](https://github.com/google/adk-java/commit/7957d9506a67b6027638db8433196698cc3716e3) docs(examples): run workflow-node agents in single-turn mode (Damian Momot, 2026-11-17)
- [84c0970d](https://github.com/google/adk-java/commit/84c0970df259d4862c7eb71d83178ebbae3095f1) docs(examples): add samples that pass an agent's answer to the next node (Damian Momot, 2026-11-17)
- [5232c334](https://github.com/google/adk-java/commit/5232c3343220a100eb95403cb48c1ea7a07c479f) chore: removing outdated pre 1.0 stable release preview notice (Damian Momot, 2026-11-17)
- [47227c0a](https://github.com/google/adk-java/commit/47227c0ab2b9c945936e6c503435d3cdbc07f65e) docs(examples): add loop and nested workflow samples (Damian Momot, 2026-11-17)

## Changed Files

- `M	README.md`
- `M	a2a/src/main/java/com/google/adk/a2a/agent/RemoteA2AAgent.java`
- `M	a2a/src/main/java/com/google/adk/a2a/converters/EventConverter.java`
- `M	a2a/src/main/java/com/google/adk/a2a/converters/ResponseConverter.java`
- `M	a2a/src/test/java/com/google/adk/a2a/agent/RemoteA2AAgentTest.java`
- `M	a2a/src/test/java/com/google/adk/a2a/converters/EventConverterTest.java`
- `M	a2a/src/test/java/com/google/adk/a2a/converters/ResponseConverterTest.java`
- `M	core/pom.xml`
- `M	core/src/main/java/com/google/adk/SchemaUtils.java`
- `M	core/src/main/java/com/google/adk/agents/Context.java`
- `M	core/src/main/java/com/google/adk/agents/InvocationContext.java`
- `M	core/src/main/java/com/google/adk/agents/LlmAgent.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/PersistBarrier.java`
- `M	core/src/main/java/com/google/adk/models/ApigeeLlm.java`
- `M	core/src/main/java/com/google/adk/runner/Runner.java`
- `M	core/src/main/java/com/google/adk/tools/AgentTool.java`
- `M	core/src/main/java/com/google/adk/tools/SetModelResponseTool.java`
- `M	core/src/main/java/com/google/adk/workflow/FunctionNode.java`
- `M	core/src/main/java/com/google/adk/workflow/FunctionNodes.java`
- `M	core/src/main/java/com/google/adk/workflow/Node.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeBody.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeExecutionState.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeInterruptedException.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `M	core/src/main/java/com/google/adk/workflow/Scheduler.java`
- `M	core/src/main/java/com/google/adk/workflow/SchemaFit.java`
- `M	core/src/test/java/com/google/adk/SchemaUtilsTest.java`
- `M	core/src/test/java/com/google/adk/agents/ContextTest.java`
- `M	core/src/test/java/com/google/adk/agents/LlmAgentTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/OutputSchemaTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/PersistBarrierTest.java`
- `M	core/src/test/java/com/google/adk/models/ApigeeLlmTest.java`
- `M	core/src/test/java/com/google/adk/runner/RunnerTest.java`
- `M	core/src/test/java/com/google/adk/tools/AgentToolTest.java`
- `M	core/src/test/java/com/google/adk/tools/SetModelResponseToolTest.java`
- `M	core/src/test/java/com/google/adk/workflow/DynamicDispatchTest.java`
- `M	core/src/test/java/com/google/adk/workflow/FunctionNodeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/NodeRunnerTest.java`
- `M	core/src/test/java/com/google/adk/workflow/SchedulerTest.java`
- `M	core/src/test/java/com/google/adk/workflow/SchemaFitTest.java`
- `A	core/src/test/java/com/google/adk/workflow/TimeOffWorkflowTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowResumeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowResumeTesting.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowRetryTest.java`
- `M	examples/workflows/ClassifierNodeWorkflow.java`
- `A	examples/workflows/DynamicFanOutFanInWorkflow.java`
- `A	examples/workflows/DynamicNodesWorkflow.java`
- `A	examples/workflows/LoopWorkflow.java`
- `A	examples/workflows/MessageTriageWorkflow.java`
- `A	examples/workflows/NestedWorkflow.java`
- `A	examples/workflows/NodeOutputWorkflow.java`
- `M	examples/workflows/OrderProcessingWorkflow.java`
- `A	examples/workflows/ParallelWorkerWorkflow.java`
- `M	examples/workflows/README.md`
- `M	examples/workflows/RequestInputAdvancedWorkflow.java`
- `M	examples/workflows/RequestInputRerunWorkflow.java`
- `M	examples/workflows/RequestInputWorkflow.java`
- `M	examples/workflows/ResearchWorkflow.java`
- `M	examples/workflows/RouteWorkflow.java`
- `A	examples/workflows/SequenceWorkflow.java`
- `A	examples/workflows/SupportTriageWorkflow.java`
- `A	examples/workflows/UseAsOutputWorkflow.java`
