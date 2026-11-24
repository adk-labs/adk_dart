# ADK Java Daily Change Report

- Date (UTC): 2026-11-24
- Source: `google/adk-java`
- Latest SHA: `548d0a13bb4fd103da2a766dfb801355fc6bfcd2`
- Previous SHA: `dde4b23de69b3ffb16393217b195bb0b056c4bb8`

## Summary

- New commits: 10

## Commits

- [548d0a13](https://github.com/google/adk-java/commit/548d0a13bb4fd103da2a766dfb801355fc6bfcd2) feat(tokt): close and cancel a Java model's live connection without hanging or leaking (Kamil Tomaszek, 2026-11-23)
- [ba9826cf](https://github.com/google/adk-java/commit/ba9826cf3da39c51a9b283a610fecd76909d16f1) fix(workflow): preserve a message output on events that also carry content (Mateusz Krawiec, 2026-11-23)
- [c34785ce](https://github.com/google/adk-java/commit/c34785ce7f6502247c0d15dc3302a13696a0e6ca) fix(a2a): keep a message reply that reports only an error code (Google Team Member, 2026-11-23)
- [e075cdf7](https://github.com/google/adk-java/commit/e075cdf7b4343ebfbd229647d12e5c39315d3ee5) fix(workflow): let a type take its own output, including keys it writes but never reads (Mateusz Krawiec, 2026-11-23)
- [6ffdca5d](https://github.com/google/adk-java/commit/6ffdca5de5e834f872978496b8835ca7e166ac0c) refactor(workflow): add a checker that converts values to a node schema's types (Mateusz Krawiec, 2026-11-23)
- [deb80010](https://github.com/google/adk-java/commit/deb80010de6cccd85cd67250243bd487af5da51c) feat(tokt): open a Kotlin LiveConnection on an ADK Java model (Kamil Tomaszek, 2026-11-23)
- [cdaa3e8f](https://github.com/google/adk-java/commit/cdaa3e8fd8fa53df9b22b5fdb28944c4a43a16b4) feat(tokt): build the live request an ADK Java model connects with (Kamil Tomaszek, 2026-11-23)
- [d910c571](https://github.com/google/adk-java/commit/d910c571d0cf063acb608274b086fcaf27d7a256) fix(workflow): rerun the model when a failed LlmAgent node retries (Damian Momot, 2026-11-23)
- [b2572c1b](https://github.com/google/adk-java/commit/b2572c1b3955ae6950b712e865abc082403aa084) fix(workflow): make node state's map views read-only and clear() throw (Mateusz Krawiec, 2026-11-23)
- [d9e5f860](https://github.com/google/adk-java/commit/d9e5f86016d87e766877305ca2c744321ae526b6) feat: fill in schema defaults for omitted properties (Damian Momot, 2026-11-23)

## Changed Files

- `M	a2a/src/main/java/com/google/adk/a2a/converters/ResponseConverter.java`
- `M	a2a/src/test/java/com/google/adk/a2a/converters/ResponseConverterTest.java`
- `M	core/src/main/java/com/google/adk/SchemaUtils.java`
- `M	core/src/main/java/com/google/adk/agents/Context.java`
- `M	core/src/main/java/com/google/adk/agents/LlmAgent.java`
- `M	core/src/main/java/com/google/adk/agents/SingleTurnAgentTool.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/StepResume.java`
- `M	core/src/main/java/com/google/adk/sessions/State.java`
- `M	core/src/main/java/com/google/adk/tools/AgentTool.java`
- `M	core/src/main/java/com/google/adk/tools/SetModelResponseTool.java`
- `M	core/src/main/java/com/google/adk/workflow/FunctionNode.java`
- `M	core/src/main/java/com/google/adk/workflow/Graph.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeInfo.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `M	core/src/main/java/com/google/adk/workflow/PortScalars.java`
- `M	core/src/main/java/com/google/adk/workflow/PortSchemas.java`
- `M	core/src/main/java/com/google/adk/workflow/ResumeScan.java`
- `M	core/src/main/java/com/google/adk/workflow/SchemaFit.java`
- `A	core/src/main/java/com/google/adk/workflow/ValueCoercer.java`
- `M	core/src/test/java/com/google/adk/SchemaUtilsTest.java`
- `M	core/src/test/java/com/google/adk/agents/ContextTest.java`
- `M	core/src/test/java/com/google/adk/agents/LlmAgentTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/StepResumeTest.java`
- `M	core/src/test/java/com/google/adk/runner/RunnerRootNodeTest.java`
- `M	core/src/test/java/com/google/adk/tools/AgentToolTest.java`
- `M	core/src/test/java/com/google/adk/tools/SetModelResponseToolTest.java`
- `M	core/src/test/java/com/google/adk/workflow/FunctionNodeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/LlmAgentAsNodeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/LlmAgentModeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/LlmAgentTaskModeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ResumeScanTest.java`
- `A	core/src/test/java/com/google/adk/workflow/ValueCoercerTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowResumeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowResumeTesting.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowRetryTest.java`
- `M	tokt/README.md`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/JavaAdkToKt.kt`
- `A	tokt/src/main/kotlin/com/google/adk/tokt/adapters/JavaLlmConnectionToKt.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/adapters/JavaModelToKt.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/FunctionDeclarationCodec.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/GenerateContentConfigCodec.kt`
- `A	tokt/src/main/kotlin/com/google/adk/tokt/codecs/LiveConnectConfigCodec.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/LlmRequestCodec.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/PartCodec.kt`
- `M	tokt/src/test/kotlin/com/google/adk/tokt/KtRunnerInteropTest.kt`
- `A	tokt/src/test/kotlin/com/google/adk/tokt/adapters/JavaLlmConnectionToKtTest.kt`
