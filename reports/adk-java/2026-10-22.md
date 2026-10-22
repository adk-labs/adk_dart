# ADK Java Daily Change Report

- Date (UTC): 2026-10-22
- Source: `google/adk-java`
- Latest SHA: `17687a92fba166ad7911766e3e59689b23d19a51`
- Previous SHA: `aab51efa5ad765622858fd844b920756a65bcd88`

## Summary

- New commits: 17

## Commits

- [17687a92](https://github.com/google/adk-java/commit/17687a92fba166ad7911766e3e59689b23d19a51) Merge pull request #1572 from Laurianti:fix-error-event-final-response (Copybara-Service, 2026-10-22)
- [da10073e](https://github.com/google/adk-java/commit/da10073e5b82f7c5f84f0186abb47cf0a392aecd) Merge pull request #1569 from Laurianti:fix-instruction-dollar-brace-placeholders (Copybara-Service, 2026-10-22)
- [6f929342](https://github.com/google/adk-java/commit/6f929342262ca9347b95ef3ac0f0462fdc9b0efd) Merge pull request #1144 from r4inee:feature/default-message-content-in-tracing-to-false (Copybara-Service, 2026-10-22)
- [4d05a08a](https://github.com/google/adk-java/commit/4d05a08a1ea8886b0b51d46d493dea841fb6fac6) Merge pull request #1391 from svetanis:feature/reflect-and-retry-tool-plugin (Copybara-Service, 2026-10-22)
- [a630ecf5](https://github.com/google/adk-java/commit/a630ecf5b6606b38b479795abcf2a9401f2e3977) Merge pull request #1673 from NewPeople-star:fix/mcp-reserved-tool-names-1513 (Copybara-Service, 2026-10-22)
- [29616c7e](https://github.com/google/adk-java/commit/29616c7e4ec909a939ac1886dd778411234e8eba) Merge pull request #1096 from mohan-ganesh:firestore-session-updatereadme (Copybara-Service, 2026-10-22)
- [52f2be71](https://github.com/google/adk-java/commit/52f2be71c5aa703cb611bddd2cd299df86bf4d10) feat: add NodeInfo.name, runId, and parentRunId, and Event.nodeName (Damian Momot, 2026-10-22)
- [e293898b](https://github.com/google/adk-java/commit/e293898bbf528fb983ff3533fa6dfb7dd7ecf346) feat: run child nodes from a workflow node with Context.runNode (Damian Momot, 2026-10-22)
- [ad1ea25f](https://github.com/google/adk-java/commit/ad1ea25fef24773ade34ff690a333cb8f441fef0) Merge pull request #1435 from prasanna8585:fix/listevents-ownership-check (Copybara-Service, 2026-10-22)
- [145901db](https://github.com/google/adk-java/commit/145901db1e7142cf15c66b7298c8116c14111883) refactor: add the runtime that runs child nodes from a workflow node (Damian Momot, 2026-10-22)
- [72b4af89](https://github.com/google/adk-java/commit/72b4af893e06b05ef032f0cb4a63ca345760124f) feat: add RunConfig.dollarEscapedPlaceholders to leave escaped placeholders in instructions as written (Laurianti, 2026-10-21)
- [ab67dc50](https://github.com/google/adk-java/commit/ab67dc5015cc3554214d7919682613e200c9e5f1) fix(events): treat an error event without function calls as a final response (Laurianti, 2026-09-28)
- [5af3854a](https://github.com/google/adk-java/commit/5af3854a27c9fa2be54b998b2883b071be667c01) docs: update firestore session service dependency versions and artifact identifiers... (Ganesh, Mohan, 2026-10-18)
- [33e9f8b2](https://github.com/google/adk-java/commit/33e9f8b2dcd88916d12621243fa6e0b1988c5bad) feat(plugins): port ReflectAndRetryToolPlugin from adk-python (svetanis, 2026-08-02)
- [81a6a047](https://github.com/google/adk-java/commit/81a6a04701ec2d7218420df0ce1e4be87d2259b6) feat: default message content capture in spans to false (Simon Su, 2026-04-16)
- [509d69d6](https://github.com/google/adk-java/commit/509d69d6025c7c9f093383114b7a86e7070cfbc9) fix: skip reserved framework names in MCP toolsets (NewPeople-star, 2026-10-17)
- [6cb6557a](https://github.com/google/adk-java/commit/6cb6557a423eab39c67da9a1ec4691e9aa8ba951) fix: enforce appName ownership check in VertexAiSessionService.listEvents (prasanna8585, 2026-10-15)

## Changed Files

- `M	contrib/firestore-session-service/README.md`
- `M	core/src/main/java/com/google/adk/agents/Context.java`
- `M	core/src/main/java/com/google/adk/agents/Instruction.java`
- `M	core/src/main/java/com/google/adk/agents/RunConfig.java`
- `M	core/src/main/java/com/google/adk/events/Event.java`
- `A	core/src/main/java/com/google/adk/plugins/ReflectAndRetryToolPlugin.java`
- `M	core/src/main/java/com/google/adk/sessions/VertexAiSessionService.java`
- `M	core/src/main/java/com/google/adk/telemetry/README.md`
- `M	core/src/main/java/com/google/adk/telemetry/Tracing.java`
- `M	core/src/main/java/com/google/adk/tools/mcp/McpAsyncToolset.java`
- `A	core/src/main/java/com/google/adk/tools/mcp/McpToolNameFilter.java`
- `M	core/src/main/java/com/google/adk/tools/mcp/McpToolset.java`
- `M	core/src/main/java/com/google/adk/utils/InstructionUtils.java`
- `A	core/src/main/java/com/google/adk/workflow/DynamicNodeFailedException.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeExecutionState.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeInfo.java`
- `A	core/src/main/java/com/google/adk/workflow/NodeInterruptedException.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `A	core/src/main/java/com/google/adk/workflow/RunNodeConfig.java`
- `M	core/src/main/java/com/google/adk/workflow/Scheduler.java`
- `M	core/src/test/java/com/google/adk/agents/ContextTest.java`
- `M	core/src/test/java/com/google/adk/agents/RunConfigTest.java`
- `M	core/src/test/java/com/google/adk/events/EventTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/InstructionsTest.java`
- `M	core/src/test/java/com/google/adk/plugins/GlobalInstructionPluginTest.java`
- `A	core/src/test/java/com/google/adk/plugins/ReflectAndRetryToolPluginTest.java`
- `M	core/src/test/java/com/google/adk/sessions/VertexAiSessionServiceTest.java`
- `M	core/src/test/java/com/google/adk/telemetry/ContextPropagationTest.java`
- `A	core/src/test/java/com/google/adk/testing/WorkflowTestNodes.java`
- `A	core/src/test/java/com/google/adk/tools/mcp/McpToolsetReservedNamesTest.java`
- `M	core/src/test/java/com/google/adk/utils/InstructionUtilsTest.java`
- `A	core/src/test/java/com/google/adk/workflow/DynamicDispatchTest.java`
- `A	core/src/test/java/com/google/adk/workflow/DynamicWorkflowTest.java`
- `M	core/src/test/java/com/google/adk/workflow/NodeInfoTest.java`
- `A	core/src/test/java/com/google/adk/workflow/RunNodeConfigTest.java`
- `M	release-please-config.json`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/RunConfigCodec.kt`
- `M	tokt/src/test/kotlin/com/google/adk/tokt/KtRunnerInteropTest.kt`
