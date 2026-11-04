# ADK Java Daily Change Report

- Date (UTC): 2026-11-04
- Source: `google/adk-java`
- Latest SHA: `587d2525c307bedebe847e01ad463a353881bb7d`
- Previous SHA: `d100738a62cf5ebf631ba9a6c288406cd999eb79`

## Summary

- New commits: 9

## Commits

- [587d2525](https://github.com/google/adk-java/commit/587d2525c307bedebe847e01ad463a353881bb7d) fix: count events after the last model response toward the compaction threshold (Google Team Member, 2026-11-04)
- [658fabaa](https://github.com/google/adk-java/commit/658fabaaa2d020160dab59fc8a64a81f63628e3c) fix: show an agent the user's answer to another agent's call (Damian Momot, 2026-11-04)
- [42b2f9c3](https://github.com/google/adk-java/commit/42b2f9c3258fbdb197eee3c4edc8f539052467a0) feat(tokt): stream a Flowable FunctionTool in a live run (Kamil Tomaszek, 2026-11-04)
- [cbc645ad](https://github.com/google/adk-java/commit/cbc645ad8b0432d77d7339bfbec1081ebe518749) refactor(dev): draw workflow graphs as DOT the way the Python dev server does (Damian Osadczuk, 2026-11-04)
- [abb86a74](https://github.com/google/adk-java/commit/abb86a742bed1a3e2628ae38c3b25be2e8f73508) fix(agents): stop saving a transfer target's reply to the parent's outputKey (Damian Momot, 2026-11-04)
- [1f1537dc](https://github.com/google/adk-java/commit/1f1537dc8c8662b9c4081b5eed40cba5e4851a76) feat(tokt): send blobs and run a held session through runLive (Kamil Tomaszek, 2026-11-04)
- [a77e5dcc](https://github.com/google/adk-java/commit/a77e5dcc647ee86861dd8825ee53150365f3889c) docs(examples): add retry, returns and route workflow samples (Damian Momot, 2026-11-04)
- [5217ce85](https://github.com/google/adk-java/commit/5217ce85231834315a6c8de5d4068587807dae48) docs(examples): add a workflows module with five samples that call no model (Damian Momot, 2026-11-04)
- [62003c12](https://github.com/google/adk-java/commit/62003c129466658d40316728b0bbb4b98578b1b5) feat(models): bring Claude to parity with ADK Python (Damian Momot, 2026-11-03)

## Changed Files

- `M	core/src/main/java/com/google/adk/agents/LlmAgent.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/Basic.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/Contents.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/OutputSchema.java`
- `M	core/src/main/java/com/google/adk/models/Claude.java`
- `M	core/src/main/java/com/google/adk/summarizer/TailRetentionEventCompactor.java`
- `M	core/src/test/java/com/google/adk/agents/LlmAgentTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/CompactionTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/ContentsTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/OutputSchemaTest.java`
- `M	core/src/test/java/com/google/adk/models/ClaudeTest.java`
- `M	core/src/test/java/com/google/adk/summarizer/TailRetentionEventCompactorTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowHitlTest.java`
- `A	dev/src/main/java/com/google/adk/web/controller/GraphPlotter.java`
- `A	dev/src/test/java/com/google/adk/web/controller/GraphPlotterTest.java`
- `M	examples/README.md`
- `M	examples/pom.xml`
- `A	examples/workflows/FanOutFanInWorkflow.java`
- `A	examples/workflows/LoopSelfWorkflow.java`
- `A	examples/workflows/MessageWorkflow.java`
- `A	examples/workflows/MultiTriggersWorkflow.java`
- `A	examples/workflows/README.md`
- `A	examples/workflows/RetryWorkflow.java`
- `A	examples/workflows/ReturnsWorkflow.java`
- `A	examples/workflows/RouteWorkflow.java`
- `A	examples/workflows/StateWorkflow.java`
- `A	examples/workflows/pom.xml`
- `M	pom.xml`
- `M	tokt/README.md`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/JavaAdkToKt.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/KtRunnerToJava.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/adapters/JavaToolToKt.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/PartCodec.kt`
- `M	tokt/src/test/kotlin/com/google/adk/tokt/KtRunnerInteropTest.kt`
