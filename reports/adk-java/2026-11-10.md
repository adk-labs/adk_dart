# ADK Java Daily Change Report

- Date (UTC): 2026-11-10
- Source: `google/adk-java`
- Latest SHA: `f98506455b16436261c0fe8d17b939c7bf1bd387`
- Previous SHA: `61e0eb80f4b7bcdabb21637141d7936d3e4053e3`

## Summary

- New commits: 13

## Commits

- [f9850645](https://github.com/google/adk-java/commit/f98506455b16436261c0fe8d17b939c7bf1bd387) fix(workflow): pause a tool node when its tool asks for confirmation (Damian Momot, 2026-11-10)
- [5ce839b4](https://github.com/google/adk-java/commit/5ce839b44c6860cefcd1b689d682326df1142bd8) feat: let models report whether they take an output schema with tools (Mateusz Krawiec, 2026-11-10)
- [8a9b6d03](https://github.com/google/adk-java/commit/8a9b6d034237476ec5549d9d123196dc7f7564f6) fix(langchain4j): end a streamed turn with one response that holds the whole answer (Miłosz Sobczyk, 2026-11-10)
- [a4182a54](https://github.com/google/adk-java/commit/a4182a544a28363162ca052c07c02b0f1ca1dfdb) fix(spring-ai): report cached prompt tokens in usage metadata (Mateusz Krawiec, 2026-11-10)
- [87468e2d](https://github.com/google/adk-java/commit/87468e2d241409c356373b0482c1784839722b18) docs(examples): add a classifier node workflow sample (Damian Momot, 2026-11-10)
- [17b4f8ca](https://github.com/google/adk-java/commit/17b4f8ca8231ac81d8b7435b5720a24c21ee3c66) Merge pull request #1747 from dibyo10:fix/bqaa-gcs-create-only-upload (Copybara-Service, 2026-11-10)
- [464cf487](https://github.com/google/adk-java/commit/464cf487f62038b9bdb567296c810f27bc354644) fix(dev): listen on 127.0.0.1 by default in AdkWebServer.main() and start() (Mateusz Krawiec, 2026-11-10)
- [c573d936](https://github.com/google/adk-java/commit/c573d9369207924d5e3c2d1bcb48b0084c942ff2) Merge pull request #1737 from pcbeingused333:fix/openai-cached-tokens (Copybara-Service, 2026-11-10)
- [6a497dac](https://github.com/google/adk-java/commit/6a497dac6d94b97a3345e9c347a8409acddde717) fix(plugins): make BQAA GCS uploads create-only so transient errors retry (Dibyo Chakraborty, 2026-11-03)
- [a9680883](https://github.com/google/adk-java/commit/a9680883acdf1a2bd25050bf7dd1eaa66b9c6100) docs(examples): add research and order-processing workflow samples (Damian Momot, 2026-11-10)
- [c29d0a20](https://github.com/google/adk-java/commit/c29d0a20670009e26995759f6f9a62853368c556) Merge pull request #1783 from glaforge:chore/upgrade-langchain4j-1.23.0 (Copybara-Service, 2026-11-10)
- [1869fb5a](https://github.com/google/adk-java/commit/1869fb5a37a9c26ee7434de13ff6ae34d01c004c) chore(deps): upgrade LangChain4j to 1.23.0 (Guillaume Laforge, 2026-11-10)
- [3fad1ee7](https://github.com/google/adk-java/commit/3fad1ee7192065eed3351a1742a4f8814cd3be3d) fix(models): map cached_tokens to cachedContentTokenCount in Chat Completions usage (Alex Castillo, 2026-10-31)

## Changed Files

- `M	contrib/langchain4j/src/main/java/com/google/adk/models/langchain4j/LangChain4j.java`
- `M	contrib/langchain4j/src/test/java/com/google/adk/models/langchain4j/LangChain4jIntegrationTest.java`
- `M	contrib/langchain4j/src/test/java/com/google/adk/models/langchain4j/LangChain4jTest.java`
- `M	contrib/spring-ai/src/main/java/com/google/adk/models/springai/MessageConverter.java`
- `M	contrib/spring-ai/src/test/java/com/google/adk/models/springai/MessageConverterTest.java`
- `M	contrib/spring-ai/src/test/java/com/google/adk/models/springai/SpringAIIntegrationTest.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/OutputSchema.java`
- `M	core/src/main/java/com/google/adk/models/BaseLlm.java`
- `M	core/src/main/java/com/google/adk/models/Claude.java`
- `A	core/src/main/java/com/google/adk/models/LlmCapabilities.java`
- `M	core/src/main/java/com/google/adk/models/chat/ChatCompletionsResponse.java`
- `M	core/src/main/java/com/google/adk/plugins/agentanalytics/GcsOffloader.java`
- `M	core/src/main/java/com/google/adk/utils/ModelNameUtils.java`
- `M	core/src/main/java/com/google/adk/workflow/ToolNodes.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/OutputSchemaTest.java`
- `M	core/src/test/java/com/google/adk/models/ClaudeTest.java`
- `M	core/src/test/java/com/google/adk/models/chat/ChatCompletionsResponseTest.java`
- `M	core/src/test/java/com/google/adk/plugins/agentanalytics/BigQueryAgentAnalyticsPluginTest.java`
- `M	core/src/test/java/com/google/adk/plugins/agentanalytics/GcsOffloaderTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ToolNodesTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowHitlTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowResumeTesting.java`
- `M	dev/README.md`
- `M	dev/src/main/java/com/google/adk/web/AdkWebServer.java`
- `M	dev/src/test/java/com/google/adk/web/AdkWebServerStartTest.java`
- `A	examples/workflows/ClassifierNodeWorkflow.java`
- `A	examples/workflows/OrderProcessingWorkflow.java`
- `M	examples/workflows/README.md`
- `A	examples/workflows/ResearchWorkflow.java`
- `M	pom.xml`
