# ADK Java Daily Change Report

- Date (UTC): 2026-10-15
- Source: `google/adk-java`
- Latest SHA: `0ee0d4bb43d9cb8b48a7318158f4c0177450f49d`
- Previous SHA: `39e06a71cbd902d3d31933e67867bc1fbb4272b3`

## Summary

- New commits: 11

## Commits

- [0ee0d4bb](https://github.com/google/adk-java/commit/0ee0d4bb43d9cb8b48a7318158f4c0177450f49d) Merge pull request #1565 from innoprej:fix/llm-flow-step-loop (Copybara-Service, 2026-10-15)
- [bad4f4c3](https://github.com/google/adk-java/commit/bad4f4c3e64fe2a86bb373977f1b1f3477c15de2) Merge pull request #1540 from innoprej:build/quote-mockito-javaagent (Copybara-Service, 2026-10-15)
- [0b1303e1](https://github.com/google/adk-java/commit/0b1303e1f641c93bb3c679a1898741575d348e15) Merge pull request #1557 from innoprej:test/apigee-proxy-url-execution (Copybara-Service, 2026-10-15)
- [ed5423ea](https://github.com/google/adk-java/commit/ed5423ea9e1b7b25f27e01b938ac906347c7aee2) Merge pull request #1558 from innoprej:docs/bug-report-java-version (Copybara-Service, 2026-10-15)
- [2ab4d32e](https://github.com/google/adk-java/commit/2ab4d32e12439232f6c39cdfe835491f41700fb7) Merge pull request #1625 from zh-hanlabs:docs/component-registry-orphan-javadoc (Copybara-Service, 2026-10-15)
- [60250a93](https://github.com/google/adk-java/commit/60250a930ec50b9e63a4bef8b6d3949fa0b31817) fix(mcp): emit valid JSON Schema when converting ADK tools to MCP tools (Kamil Tomaszek, 2026-10-14)
- [31ac2dfb](https://github.com/google/adk-java/commit/31ac2dfb920aaf3989c356186ecb0b14f503caa0) fix(flows): avoid StackOverflowError after many steps in BaseLlmFlow (Jaehee Shin, 2026-09-26)
- [09a14962](https://github.com/google/adk-java/commit/09a14962f3fb70f0bfbeea7eeee33863d6cb94aa) docs: attach orphaned javadoc to resolveToolInstance in ComponentRegistry (zh-hanlabs, 2026-09-27)
- [f1b8a663](https://github.com/google/adk-java/commit/f1b8a663bb32b635c9da40df87637dbc25781e8d) docs: ask for the Java version in the bug report template (Jaehee Shin, 2026-09-25)
- [381d374c](https://github.com/google/adk-java/commit/381d374c7bc083e63e9f78c669065c47cba758ca) test: point apigee-llm-proxy-url at the renamed test method (Jaehee Shin, 2026-09-25)
- [a9bb99e0](https://github.com/google/adk-java/commit/a9bb99e0a0a3f5eb3e62267d3da40e038fa1340a) build: quote the Mockito -javaagent path in surefire argLine (Jaehee Shin, 2026-09-23)

## Changed Files

- `M	.github/ISSUE_TEMPLATE/bug_report.md`
- `M	a2a/pom.xml`
- `M	contrib/firestore-session-service/pom.xml`
- `M	contrib/langchain4j/pom.xml`
- `M	contrib/planners/pom.xml`
- `M	contrib/spring-ai/pom.xml`
- `M	core/pom.xml`
- `M	core/src/main/java/com/google/adk/flows/llmflows/BaseLlmFlow.java`
- `M	core/src/main/java/com/google/adk/models/chat/ChatCompletionsRequest.java`
- `M	core/src/main/java/com/google/adk/tools/mcp/ConversionUtils.java`
- `M	core/src/main/java/com/google/adk/utils/ComponentRegistry.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/BaseLlmFlowTest.java`
- `M	core/src/test/java/com/google/adk/tools/mcp/ConversionUtilsTest.java`
- `M	dev/pom.xml`
- `M	pom.xml`
