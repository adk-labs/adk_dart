# ADK Java Daily Change Report

- Date (UTC): 2026-11-09
- Source: `google/adk-java`
- Latest SHA: `61e0eb80f4b7bcdabb21637141d7936d3e4053e3`
- Previous SHA: `4dfe0b57fe2a5548cc9a49d1e06e87ad8b85713e`

## Summary

- New commits: 5

## Commits

- [61e0eb80](https://github.com/google/adk-java/commit/61e0eb80f4b7bcdabb21637141d7936d3e4053e3) feat(classifiers): add ClassifierNode for workflow routing (Rafal Glowinski, 2026-11-09)
- [a8d9dfbb](https://github.com/google/adk-java/commit/a8d9dfbb9a487992600608790e1c4fc0cd0038ee) Merge pull request #1649 from codingkiddo:fix/synchronous-model-error-callbacks (Copybara-Service, 2026-11-09)
- [7fb0a3b3](https://github.com/google/adk-java/commit/7fb0a3b3e2aa0aaa4b7f0c0f50656e991dcc6c4a) fix: let a sub-agent transfer back to its parent in a resumed invocation (Damian Momot, 2026-11-09)
- [e8682932](https://github.com/google/adk-java/commit/e8682932d8d0815103c02ea295b25abec35f9e5f) fix(tools): keep the null of a required nullable property in `set_model_response` (Miłosz Sobczyk, 2026-11-08)
- [e5cd285c](https://github.com/google/adk-java/commit/e5cd285c76d81595b003e0b5360b1ca2c081abc8) fix(flows): run onModelErrorCallback when a model throws synchronously (Vinod Kumar, 2026-11-04)

## Changed Files

- `M	core/src/main/java/com/google/adk/agents/LlmAgent.java`
- `A	core/src/main/java/com/google/adk/classifiers/ClassifierNode.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/BaseLlmFlow.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/StepResume.java`
- `M	core/src/main/java/com/google/adk/tools/SetModelResponseTool.java`
- `M	core/src/main/java/com/google/adk/workflow/BaseNode.java`
- `M	core/src/main/java/com/google/adk/workflow/GraphValidation.java`
- `M	core/src/main/java/com/google/adk/workflow/GraphValidationException.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeInputValidationException.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeNames.java`
- `A	core/src/main/java/com/google/adk/workflow/WorkflowDataException.java`
- `M	core/src/test/java/com/google/adk/agents/LlmAgentTest.java`
- `A	core/src/test/java/com/google/adk/classifiers/ClassifierNodeTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/BaseLlmFlowTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/OutputSchemaTest.java`
- `A	core/src/test/java/com/google/adk/flows/llmflows/StepResumeTest.java`
- `M	core/src/test/java/com/google/adk/runner/RunnerResumabilityTest.java`
- `M	core/src/test/java/com/google/adk/tools/SetModelResponseToolTest.java`
