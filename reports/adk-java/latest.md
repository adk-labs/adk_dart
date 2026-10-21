# ADK Java Daily Change Report

- Date (UTC): 2026-10-21
- Source: `google/adk-java`
- Latest SHA: `aab51efa5ad765622858fd844b920756a65bcd88`
- Previous SHA: `833cbd5751f615ecc162ef99a6c380f97c7d9144`

## Summary

- New commits: 10

## Commits

- [aab51efa](https://github.com/google/adk-java/commit/aab51efa5ad765622858fd844b920756a65bcd88) fix: resume Kotlin workflows behind an adapted Java session service (Damian Momot, 2026-10-21)
- [5f49fea4](https://github.com/google/adk-java/commit/5f49fea45ed5f2d1b50b18165ea5370e9a55735a) Merge pull request #1573 from Laurianti:fix-memory-search-word-matching (Copybara-Service, 2026-10-21)
- [9837e1b1](https://github.com/google/adk-java/commit/9837e1b15bfb51ef2e20bea13612792f22f0b832) fix: restrict turn-based `transfer_to_agent` to declared targets (Kamil Tomaszek, 2026-10-21)
- [db305533](https://github.com/google/adk-java/commit/db305533bd7ed383a6e5a4bcb6339678706a4c8e) Merge pull request #1659 from google:release-please--branches--main (Copybara-Service, 2026-10-21)
- [3219af6e](https://github.com/google/adk-java/commit/3219af6e1d44e7654ecf0fffe61ac86ff82a4ef7) chore(main): release 1.13.0 (adk-java-releases-bot, 2026-10-21)
- [cecad8f4](https://github.com/google/adk-java/commit/cecad8f49e7ce58aea790ab598753f1475b685dd) feat: run a workflow graph (Damian Momot, 2026-10-21)
- [66eab8cc](https://github.com/google/adk-java/commit/66eab8cc448297708c162838bd45519885c47ad4) feat: run a workflow node as the invocation root (Damian Momot, 2026-10-21)
- [1ae50780](https://github.com/google/adk-java/commit/1ae5078072e13e101318e32833f1db323ef084e1) fix(dev): reject DNS-rebinding requests that reach the server over loopback (Mateusz Krawiec, 2026-10-21)
- [5667d382](https://github.com/google/adk-java/commit/5667d382ab5078a0d6e8f7184713a6bab767e004) fix(dev): allow only same-origin requests by default for CORS and /run_live (Mateusz Krawiec, 2026-10-21)
- [008d4095](https://github.com/google/adk-java/commit/008d409599e9be48dc9afdc936e3a71561a7cdf7) fix(memory): tokenize query and events alike in InMemoryMemoryService (Laurianti, 2026-09-28)

## Changed Files

- `M	.release-please-manifest.json`
- `M	CHANGELOG.md`
- `M	README.md`
- `M	a2a/pom.xml`
- `M	contrib/firestore-session-service/pom.xml`
- `M	contrib/langchain4j/pom.xml`
- `M	contrib/planners/pom.xml`
- `M	contrib/spring-ai/pom.xml`
- `M	core/pom.xml`
- `M	core/src/main/java/com/google/adk/Version.java`
- `M	core/src/main/java/com/google/adk/agents/BaseAgent.java`
- `M	core/src/main/java/com/google/adk/agents/InvocationContext.java`
- `M	core/src/main/java/com/google/adk/agents/LlmAgent.java`
- `A	core/src/main/java/com/google/adk/agents/NodeViewAgent.java`
- `A	core/src/main/java/com/google/adk/agents/TransferRejectedException.java`
- `M	core/src/main/java/com/google/adk/apps/App.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/BaseLlmFlow.java`
- `M	core/src/main/java/com/google/adk/memory/InMemoryMemoryService.java`
- `M	core/src/main/java/com/google/adk/runner/Runner.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeExecutionState.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `A	core/src/main/java/com/google/adk/workflow/NodeState.java`
- `A	core/src/main/java/com/google/adk/workflow/NodeStatus.java`
- `A	core/src/main/java/com/google/adk/workflow/Scheduler.java`
- `A	core/src/main/java/com/google/adk/workflow/Trigger.java`
- `A	core/src/main/java/com/google/adk/workflow/TriggerQueue.java`
- `M	core/src/main/java/com/google/adk/workflow/Workflow.java`
- `A	core/src/main/java/com/google/adk/workflow/WorkflowConfigurationException.java`
- `M	core/src/test/java/com/google/adk/agents/BaseAgentTest.java`
- `M	core/src/test/java/com/google/adk/agents/InvocationContextTest.java`
- `M	core/src/test/java/com/google/adk/agents/LlmAgentTest.java`
- `A	core/src/test/java/com/google/adk/agents/NodeViewAgentTest.java`
- `A	core/src/test/java/com/google/adk/apps/AppTest.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/AgentTransferTest.java`
- `M	core/src/test/java/com/google/adk/memory/InMemoryMemoryServiceTest.java`
- `A	core/src/test/java/com/google/adk/runner/RunnerRootNodeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/NodeExecutionStateTest.java`
- `M	core/src/test/java/com/google/adk/workflow/NodeRunnerTest.java`
- `A	core/src/test/java/com/google/adk/workflow/SchedulerTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowTest.java`
- `M	dev/README.md`
- `M	dev/pom.xml`
- `M	dev/src/main/java/com/google/adk/web/config/AdkWebCorsConfig.java`
- `M	dev/src/main/java/com/google/adk/web/config/AdkWebCorsProperties.java`
- `A	dev/src/main/java/com/google/adk/web/config/OriginGuardFilter.java`
- `A	dev/src/test/java/com/google/adk/web/AdkWebServerCorsTest.java`
- `A	dev/src/test/java/com/google/adk/web/AdkWebServerDnsRebindingTest.java`
- `M	dev/src/test/java/com/google/adk/web/AdkWebServerProxyRedirectTest.java`
- `M	dev/src/test/java/com/google/adk/web/BackendUrlRedirectTest.java`
- `M	dev/src/test/java/com/google/adk/web/controller/RuntimeConfigControllerTest.java`
- `M	examples/a2a_basic/pom.xml`
- `M	examples/a2a_server/pom.xml`
- `M	examples/configagent/pom.xml`
- `M	examples/contextcaching/pom.xml`
- `M	examples/helloworld/pom.xml`
- `M	examples/mcpfilesystem/pom.xml`
- `M	examples/pom.xml`
- `M	maven_plugin/README.md`
- `M	maven_plugin/examples/custom_tools/pom.xml`
- `M	maven_plugin/examples/simple-agent/pom.xml`
- `M	maven_plugin/pom.xml`
- `M	maven_plugin/src/main/java/com/google/adk/maven/WebMojo.java`
- `M	pom.xml`
- `M	tokt/pom.xml`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/JavaAdkToKt.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/adapters/ActionReconciler.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/EventCodec.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/KtToJavaCodecs.kt`
- `A	tokt/src/main/kotlin/com/google/adk/tokt/codecs/WorkflowCodec.kt`
- `M	tokt/src/test/kotlin/com/google/adk/tokt/KtRunnerInteropTest.kt`
- `M	tutorials/city-time-weather/pom.xml`
- `M	tutorials/live-audio-single-agent/pom.xml`
