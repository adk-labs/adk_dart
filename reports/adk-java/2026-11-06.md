# ADK Java Daily Change Report

- Date (UTC): 2026-11-06
- Source: `google/adk-java`
- Latest SHA: `a0cc1dcd0ba2d2337124d5f009860cf6a48f172b`
- Previous SHA: `406e2aefda011babd90fd2be583a8f0c12f32dc7`

## Summary

- New commits: 4

## Commits

- [a0cc1dcd](https://github.com/google/adk-java/commit/a0cc1dcd0ba2d2337124d5f009860cf6a48f172b) feat: check workflow edges by assignability (Mateusz Krawiec, 2026-11-06)
- [020c95cc](https://github.com/google/adk-java/commit/020c95ccf35506abca8700a32a7e61fb40a20ca7) feat: infer schemas for FunctionNode ports (Mateusz Krawiec, 2026-11-06)
- [01f899fb](https://github.com/google/adk-java/commit/01f899fb84ae76bb618b8272c3ce5fcad63ff37e) feat: add TypeReference ports and a build-time port check to FunctionNode (Mateusz Krawiec, 2026-11-06)
- [d627147b](https://github.com/google/adk-java/commit/d627147b0ee620119cb2293776ad8acf0d7c7b65) feat: add FunctionNode, a workflow step with typed Java ports (Mateusz Krawiec, 2026-11-06)

## Changed Files

- `M	core/src/main/java/com/google/adk/agents/InvocationContext.java`
- `M	core/src/main/java/com/google/adk/runner/Runner.java`
- `A	core/src/main/java/com/google/adk/workflow/FunctionNode.java`
- `A	core/src/main/java/com/google/adk/workflow/FunctionNodes.java`
- `M	core/src/main/java/com/google/adk/workflow/Graph.java`
- `M	core/src/main/java/com/google/adk/workflow/Node.java`
- `A	core/src/main/java/com/google/adk/workflow/NodeBody.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeExecutionState.java`
- `A	core/src/main/java/com/google/adk/workflow/NodeInputValidationException.java`
- `A	core/src/main/java/com/google/adk/workflow/PortCodec.java`
- `A	core/src/main/java/com/google/adk/workflow/PortSchemas.java`
- `A	core/src/main/java/com/google/adk/workflow/RequiredProperties.java`
- `A	core/src/main/java/com/google/adk/workflow/SchemaFit.java`
- `M	core/src/main/java/com/google/adk/workflow/Workflow.java`
- `A	core/src/test/java/com/google/adk/workflow/FunctionNodeTest.java`
- `A	core/src/test/java/com/google/adk/workflow/SchemaFitTest.java`
