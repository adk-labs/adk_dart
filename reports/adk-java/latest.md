# ADK Java Daily Change Report

- Date (UTC): 2026-10-12
- Source: `google/adk-java`
- Latest SHA: `dbc973bfcfc1b23ca04fed3cf8f8bb84f03ab160`
- Previous SHA: `189d463a9988d5235ccf34de6a6fab1aae779d20`

## Summary

- New commits: 4

## Commits

- [dbc973bf](https://github.com/google/adk-java/commit/dbc973bfcfc1b23ca04fed3cf8f8bb84f03ab160) feat: make BaseAgent extend BaseNode so every agent is a workflow node (Damian Momot, 2026-10-12)
- [a358de84](https://github.com/google/adk-java/commit/a358de84d49d0ce78fa4ff92086f03603a6f95c6) Merge pull request #1617 from caps-xia:fix/1609-tool-converter-enum-items (Copybara-Service, 2026-10-12)
- [845d9e5c](https://github.com/google/adk-java/commit/845d9e5cfe5362fde301979b1056f3cc86cc978f) refactor: prepare adk java for automatic continuation (Damian Momot, 2026-10-12)
- [7b1a5b80](https://github.com/google/adk-java/commit/7b1a5b800e9dd3f3329976e708585b7404a3a3e4) fix(spring-ai): preserve enum and items in tool schema conversion (jixing.xia, 2026-10-05)

## Changed Files

- `M	contrib/spring-ai/src/main/java/com/google/adk/models/springai/ToolConverter.java`
- `M	contrib/spring-ai/src/test/java/com/google/adk/models/springai/ToolConverterTest.java`
- `M	core/src/main/java/com/google/adk/agents/BaseAgent.java`
- `M	core/src/main/java/com/google/adk/agents/LlmAgent.java`
- `M	core/src/main/java/com/google/adk/models/Gemini.java`
- `M	core/src/test/java/com/google/adk/agents/BaseAgentTest.java`
