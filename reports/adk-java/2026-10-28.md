# ADK Java Daily Change Report

- Date (UTC): 2026-10-28
- Source: `google/adk-java`
- Latest SHA: `b7f45e2b54c5331c847e6ceb26ed24f09f8d13ee`
- Previous SHA: `461f7d6fd9d7fc1ee99e7bf3a788040810caf7d3`

## Summary

- New commits: 9

## Commits

- [b7f45e2b](https://github.com/google/adk-java/commit/b7f45e2b54c5331c847e6ceb26ed24f09f8d13ee) Merge pull request #1629 from innoprej:fix/gemini-placeholder-parity (Copybara-Service, 2026-10-28)
- [8b560fcb](https://github.com/google/adk-java/commit/8b560fcb363d95e7327624aecb651ff466904cf4) feat: run a tool as a workflow node (Miłosz Sobczyk, 2026-10-28)
- [3a4742e4](https://github.com/google/adk-java/commit/3a4742e4162961b294d0e9c2afb51a3ced0e2d94) fix: stream partial chunks, then one aggregated response (Rafal Glowinski, 2026-10-28)
- [7674c2ba](https://github.com/google/adk-java/commit/7674c2baf2ac8bfa517d358aa2580ad0ad51ae61) feat: validate workflow graphs at construction time (Damian Osadczuk, 2026-10-28)
- [08d4b62a](https://github.com/google/adk-java/commit/08d4b62ab74057e35ff8799c5d808931e1b2a100) feat: reject node names that corrupt node paths (Damian Osadczuk, 2026-10-28)
- [fd8c3605](https://github.com/google/adk-java/commit/fd8c3605cb30787d579fd83ad5f8ebe62be9a394) fix: never retry a WorkflowConfigurationException (Damian Momot, 2026-10-28)
- [921d59a2](https://github.com/google/adk-java/commit/921d59a23d970640b18656ec8ecf7c7143c8c0ec) Merge pull request #1432 from svetanis:feature/debug-logging-plugin (Copybara-Service, 2026-10-28)
- [3c3633e0](https://github.com/google/adk-java/commit/3c3633e013ec46b2e930d818eb1004e6552aab7c) feat(plugins): port DebugLoggingPlugin from adk-python (svetanis, 2026-08-14)
- [234d7dcb](https://github.com/google/adk-java/commit/234d7dcba078951184f7f6b3760977f92560608a) fix(core): align Gemini placeholder user turns with ADK Python (Jaehee Shin, 2026-10-08)

## Changed Files

- `M	contrib/spring-ai/src/main/java/com/google/adk/models/springai/SpringAI.java`
- `M	contrib/spring-ai/src/test/java/com/google/adk/models/springai/SpringAITest.java`
- `M	core/src/main/java/com/google/adk/models/GeminiUtil.java`
- `A	core/src/main/java/com/google/adk/plugins/DebugLoggingPlugin.java`
- `M	core/src/main/java/com/google/adk/workflow/Graph.java`
- `A	core/src/main/java/com/google/adk/workflow/GraphValidation.java`
- `A	core/src/main/java/com/google/adk/workflow/GraphValidationException.java`
- `M	core/src/main/java/com/google/adk/workflow/JoinNode.java`
- `A	core/src/main/java/com/google/adk/workflow/NodeNames.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `M	core/src/main/java/com/google/adk/workflow/RetryConfig.java`
- `M	core/src/main/java/com/google/adk/workflow/RunNodeConfig.java`
- `A	core/src/main/java/com/google/adk/workflow/ToolNodes.java`
- `M	core/src/main/java/com/google/adk/workflow/Workflow.java`
- `M	core/src/test/java/com/google/adk/models/GeminiUtilTest.java`
- `A	core/src/test/java/com/google/adk/plugins/DebugLoggingPluginTest.java`
- `M	core/src/test/java/com/google/adk/runner/RunnerRootNodeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/GraphTest.java`
- `A	core/src/test/java/com/google/adk/workflow/GraphValidationTest.java`
- `M	core/src/test/java/com/google/adk/workflow/JoinNodeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/RetryConfigTest.java`
- `A	core/src/test/java/com/google/adk/workflow/ToolNodesTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowRetryTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowTest.java`
