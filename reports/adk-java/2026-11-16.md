# ADK Java Daily Change Report

- Date (UTC): 2026-11-16
- Source: `google/adk-java`
- Latest SHA: `ef1335e8ea4b3618b2adb66b3e01e2caff23ec99`
- Previous SHA: `be4984ed2e15bb9795cc0cc6d538048f7b3cd146`

## Summary

- New commits: 15

## Commits

- [ef1335e8](https://github.com/google/adk-java/commit/ef1335e8ea4b3618b2adb66b3e01e2caff23ec99) fix(workflow): run parallelNode items concurrently when they block their threads (Damian Momot, 2026-11-16)
- [a33af4c3](https://github.com/google/adk-java/commit/a33af4c39cb8d3b038f4427791370a7eb23ee9c3) fix: declare set_model_response parameters as an object for untyped schemas (Mateusz Krawiec, 2026-11-16)
- [6e913486](https://github.com/google/adk-java/commit/6e913486aad54ce655010d5fd0ccff9365b446f4) fix(workflow): treat a null confirmed in a tool node's answer as a rejection (Mateusz Krawiec, 2026-11-16)
- [def4ffa8](https://github.com/google/adk-java/commit/def4ffa8786f154a845e1edd5566a48a4b2dc01e) fix(gemini): build lists from streamed function call argument paths (Mateusz Krawiec, 2026-11-16)
- [c7f906c2](https://github.com/google/adk-java/commit/c7f906c2bbeec790e7eb9b683b0ccdc93afe21e2) fix(workflow): don't start a canceled FunctionNode's confirmation predicate (Mateusz Krawiec, 2026-11-16)
- [8ddd5b42](https://github.com/google/adk-java/commit/8ddd5b4238f0fb87aea8ec1650558e4927551625) feat(workflow): reject port types that ADK Kotlin rejects, such as ZoneId (Mateusz Krawiec, 2026-11-16)
- [8c15ce53](https://github.com/google/adk-java/commit/8c15ce53bc84703085c680b316f53ecdcc260eb2) fix(langchain4j): accept free-form schemas in tool declarations (Mateusz Krawiec, 2026-11-16)
- [3fd6c1aa](https://github.com/google/adk-java/commit/3fd6c1aa9640cb385615e1ed663e659e98b30d55) fix(workflow): wait for a canceled FunctionNode body before a retry (Mateusz Krawiec, 2026-11-16)
- [e10a7b6d](https://github.com/google/adk-java/commit/e10a7b6d68d338c7567fd4bff0d96235ed135186) fix: stop logging model input and output in Gemini (Mateusz Krawiec, 2026-11-16)
- [fca65ef0](https://github.com/google/adk-java/commit/fca65ef0f8164b940422f44333790573a5b3db9f) fix(workflow): keep a state write made while NodeRunner moves pending deltas (Mateusz Krawiec, 2026-11-16)
- [f14e1845](https://github.com/google/adk-java/commit/f14e18457cc6f94d177a6bcb1e7e941ab0bd9fc7) feat: keep a `SINGLE_TURN` `LlmAgent` node to its own node path (Miłosz Sobczyk, 2026-11-16)
- [0f1b2c82](https://github.com/google/adk-java/commit/0f1b2c82071b97e139f9d3f2e39d0ea3b3ff7803) feat: hide another node's input from an agent node (Miłosz Sobczyk, 2026-11-16)
- [8e566930](https://github.com/google/adk-java/commit/8e5669307d3a0e89e946073e01c61fe21d0adab2) feat: run a `SINGLE_TURN` `LlmAgent` node without history by default (Miłosz Sobczyk, 2026-11-16)
- [d1223383](https://github.com/google/adk-java/commit/d12233836c5bc858037fd0315ca5c562cd999218) feat: make a `SINGLE_TURN` `LlmAgent` node's answer its output (Miłosz Sobczyk, 2026-11-16)
- [e264177a](https://github.com/google/adk-java/commit/e264177a8099d144eeb671b8d25c904041f76074) feat: run a `SINGLE_TURN` `LlmAgent` node on its node input (Miłosz Sobczyk, 2026-11-16)

## Changed Files

- `M	contrib/langchain4j/src/main/java/com/google/adk/models/langchain4j/LangChain4j.java`
- `M	contrib/langchain4j/src/test/java/com/google/adk/models/langchain4j/LangChain4jTest.java`
- `M	core/src/main/java/com/google/adk/SchemaUtils.java`
- `A	core/src/main/java/com/google/adk/agents/AgentMode.java`
- `M	core/src/main/java/com/google/adk/agents/BaseAgent.java`
- `M	core/src/main/java/com/google/adk/agents/InvocationContext.java`
- `M	core/src/main/java/com/google/adk/agents/LlmAgent.java`
- `M	core/src/main/java/com/google/adk/agents/Role.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/AgentTransfer.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/Contents.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/Identity.java`
- `M	core/src/main/java/com/google/adk/models/Gemini.java`
- `M	core/src/main/java/com/google/adk/tools/SetModelResponseTool.java`
- `M	core/src/main/java/com/google/adk/workflow/BaseNode.java`
- `M	core/src/main/java/com/google/adk/workflow/ConfirmationPredicate.java`
- `M	core/src/main/java/com/google/adk/workflow/FunctionNode.java`
- `M	core/src/main/java/com/google/adk/workflow/FunctionNodes.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeBody.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeConfig.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeExecutionState.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `M	core/src/main/java/com/google/adk/workflow/ParallelWorkers.java`
- `M	core/src/main/java/com/google/adk/workflow/PortCodec.java`
- `M	core/src/main/java/com/google/adk/workflow/PortSchemas.java`
- `M	core/src/main/java/com/google/adk/workflow/ResumeScan.java`
- `A	core/src/main/java/com/google/adk/workflow/ToolConfirmations.java`
- `M	core/src/main/java/com/google/adk/workflow/ToolNodes.java`
- `M	core/src/test/java/com/google/adk/SchemaUtilsTest.java`
- `M	core/src/test/java/com/google/adk/agents/InvocationContextTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/OutputSchemaTest.java`
- `M	core/src/test/java/com/google/adk/models/GeminiTest.java`
- `M	core/src/test/java/com/google/adk/workflow/FunctionNodeTest.java`
- `A	core/src/test/java/com/google/adk/workflow/LlmAgentAsNodeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/NodeRunnerTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ParallelWorkersTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ToolNodesTest.java`
