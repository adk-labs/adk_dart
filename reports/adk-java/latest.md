# ADK Java Daily Change Report

- Date (UTC): 2026-11-20
- Source: `google/adk-java`
- Latest SHA: `dde4b23de69b3ffb16393217b195bb0b056c4bb8`
- Previous SHA: `cb0c9b08f33de9a6cd2bb0dae6c082ba9c5e6a2c`

## Summary

- New commits: 7

## Commits

- [dde4b23d](https://github.com/google/adk-java/commit/dde4b23de69b3ffb16393217b195bb0b056c4bb8) revert: Revert MCP SDK version update from 2.1.0 back to 2.0.0 (Google Team Member, 2026-11-20)
- [8dbdaac7](https://github.com/google/adk-java/commit/8dbdaac7f5be0c23f9f0fed04bce93bd1de8df43) fix(workflow): keep a node's message output a message after a resume (Mateusz Krawiec, 2026-11-20)
- [86296cb0](https://github.com/google/adk-java/commit/86296cb02d10fd5be6d5256592018345e047ee50) fix(workflow): read numbers in a message's JSON as ADK Kotlin does (Mateusz Krawiec, 2026-11-20)
- [677e87a6](https://github.com/google/adk-java/commit/677e87a62fbb4278908e4e7510d0beebb4a92c8a) feat(workflow): read OptionalInt, OptionalLong and OptionalDouble fields like their primitives (Mateusz Krawiec, 2026-11-20)
- [4b6a0e08](https://github.com/google/adk-java/commit/4b6a0e08bae9c6d0b4be32655fe2db38d585867e) feat(workflow): reject unknown keys in genai and event FunctionNode ports (Mateusz Krawiec, 2026-11-20)
- [3cabda89](https://github.com/google/adk-java/commit/3cabda8909206451a8066bf482ed01d7bd1ea78b) feat(workflow): read numbers, booleans, chars and enums strictly in FunctionNode ports (Mateusz Krawiec, 2026-11-20)
- [7873fabf](https://github.com/google/adk-java/commit/7873fabf11202657d072559973f55e4753090505) feat(workflow): read a user message on typed FunctionNode ports (Mateusz Krawiec, 2026-11-19)

## Changed Files

- `M	core/src/main/java/com/google/adk/workflow/FunctionNode.java`
- `M	core/src/main/java/com/google/adk/workflow/FunctionNodes.java`
- `A	core/src/main/java/com/google/adk/workflow/MessageReader.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeInfo.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `M	core/src/main/java/com/google/adk/workflow/ParallelWorkers.java`
- `M	core/src/main/java/com/google/adk/workflow/PortCodec.java`
- `A	core/src/main/java/com/google/adk/workflow/PortScalars.java`
- `M	core/src/main/java/com/google/adk/workflow/ResumeScan.java`
- `M	core/src/main/java/com/google/adk/workflow/Scheduler.java`
- `M	core/src/main/java/com/google/adk/workflow/SchemaFit.java`
- `M	core/src/main/java/com/google/adk/workflow/ToolNodes.java`
- `M	core/src/test/java/com/google/adk/workflow/FunctionNodeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ParallelWorkersTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ResumeScanTest.java`
- `M	core/src/test/java/com/google/adk/workflow/SchemaFitTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ToolNodesTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowResumeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowResumeTesting.java`
- `M	pom.xml`
