# ADK Java Daily Change Report

- Date (UTC): 2026-11-02
- Source: `google/adk-java`
- Latest SHA: `30edd998914c6412276d1b9c4b72dcdfb9f97976`
- Previous SHA: `a4c8ac1ef53543b3a00075899b6499b1874bc90d`

## Summary

- New commits: 13

## Commits

- [30edd998](https://github.com/google/adk-java/commit/30edd998914c6412276d1b9c4b72dcdfb9f97976) feat(tokt): carry transcriptions and turnComplete across the interop (Kamil Tomaszek, 2026-11-02)
- [e3a9859b](https://github.com/google/adk-java/commit/e3a9859b9b5e558e658ab495626142fec62fab2f) Merge pull request #1743 from google:release-please--branches--main (Copybara-Service, 2026-11-02)
- [a3c0ffae](https://github.com/google/adk-java/commit/a3c0ffaec26a02fd931393bdf74336daec2b02bf) chore(main): release 1.14.1-SNAPSHOT (adk-java-releases-bot, 2026-11-02)
- [94b5bacd](https://github.com/google/adk-java/commit/94b5bacdb1c037ab162ffb88abee570ade8dfdec) fix(plugins): prevent BQAA offload data loss and preserve binary MIME (Google Team Member, 2026-11-02)
- [b45fae72](https://github.com/google/adk-java/commit/b45fae72c2b5a132070bdd2a8cdc5ad9ff783fda) chore(main): release 1.14.0 (adk-java-releases-bot, 2026-11-02)
- [ac542d67](https://github.com/google/adk-java/commit/ac542d67ea9806dde16a94c1a8d4d5fedbecb67d) fix: recover compacted function calls and pair reused call IDs in LLM content assembly (Google Team Member, 2026-11-02)
- [fc895fdb](https://github.com/google/adk-java/commit/fc895fdbb268ce05d68c981ba01865e81c5b29e9) Merge pull request #1681 from google:release-please--branches--main (Copybara-Service, 2026-11-02)
- [1ca16b9d](https://github.com/google/adk-java/commit/1ca16b9dd8524c2b58327a245cddd11b24868542) chore(main): release 1.13.1-SNAPSHOT (adk-java-releases-bot, 2026-11-02)
- [a79b61bb](https://github.com/google/adk-java/commit/a79b61bb0443fc7b7af24036dae5d12a9c1dcf77) Merge pull request #1696 from svetanis:fix/runner-resume-callback-data (Copybara-Service, 2026-11-02)
- [6fd21b55](https://github.com/google/adk-java/commit/6fd21b55965ca99f26e8e52cc779682b2e7ac53d) feat: serve an app's structure, including workflow graphs (Damian Osadczuk, 2026-11-02)
- [9c3d5509](https://github.com/google/adk-java/commit/9c3d5509b32a9e0cedd5d594d6969b9c117d7d5e) feat: load apps, agents and workflows through AppLoader (Damian Osadczuk, 2026-11-02)
- [a155d300](https://github.com/google/adk-java/commit/a155d300be53e3cb4ff6c7e4c1ca5d16606907cb) fix(workflow): fix replay branches and shared runs on resume (Damian Momot, 2026-11-02)
- [08876c43](https://github.com/google/adk-java/commit/08876c43e098837f890e38d1bb899a65405614fd) fix(runner): keep callbackContextData on a resumed invocation (svetanis, 2026-10-23)

## Changed Files

- `M	.release-please-manifest.json`
- `M	CHANGELOG.md`
- `M	README.md`
- `M	a2a/pom.xml`
- `M	contrib/firestore-session-service/README.md`
- `M	contrib/firestore-session-service/pom.xml`
- `M	contrib/langchain4j/pom.xml`
- `M	contrib/planners/pom.xml`
- `M	contrib/spring-ai/pom.xml`
- `M	core/pom.xml`
- `M	core/src/main/java/com/google/adk/Version.java`
- `M	core/src/main/java/com/google/adk/flows/llmflows/Contents.java`
- `M	core/src/main/java/com/google/adk/plugins/agentanalytics/BigQueryLoggerConfig.java`
- `M	core/src/main/java/com/google/adk/plugins/agentanalytics/Parser.java`
- `M	core/src/main/java/com/google/adk/plugins/agentanalytics/PluginState.java`
- `M	core/src/main/java/com/google/adk/runner/Runner.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeExecutionState.java`
- `M	core/src/main/java/com/google/adk/workflow/NodeRunner.java`
- `M	core/src/main/java/com/google/adk/workflow/ResumeScan.java`
- `M	core/src/main/java/com/google/adk/workflow/Scheduler.java`
- `M	core/src/test/java/com/google/adk/flows/llmflows/ContentsTest.java`
- `M	core/src/test/java/com/google/adk/plugins/agentanalytics/BigQueryAgentAnalyticsPluginTest.java`
- `M	core/src/test/java/com/google/adk/plugins/agentanalytics/ParserTest.java`
- `M	core/src/test/java/com/google/adk/plugins/agentanalytics/PluginStateTest.java`
- `M	core/src/test/java/com/google/adk/runner/RunnerResumabilityTest.java`
- `M	core/src/test/java/com/google/adk/workflow/ResumeScanTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowResumeTest.java`
- `M	core/src/test/java/com/google/adk/workflow/WorkflowRetryTest.java`
- `M	dev/pom.xml`
- `M	dev/src/main/java/com/google/adk/web/AdkWebServer.java`
- `A	dev/src/main/java/com/google/adk/web/AppLoader.java`
- `A	dev/src/main/java/com/google/adk/web/InMemoryAppLoader.java`
- `M	dev/src/main/java/com/google/adk/web/controller/AgentController.java`
- `A	dev/src/main/java/com/google/adk/web/controller/AppGraph.java`
- `A	dev/src/main/java/com/google/adk/web/controller/AppGraphController.java`
- `M	dev/src/main/java/com/google/adk/web/controller/GraphController.java`
- `M	dev/src/main/java/com/google/adk/web/service/RunnerService.java`
- `A	dev/src/main/java/com/google/adk/web/service/ServedApps.java`
- `A	dev/src/test/java/com/google/adk/web/AdkWebServerAppLoaderTest.java`
- `A	dev/src/test/java/com/google/adk/web/AdkWebServerAppRunTest.java`
- `A	dev/src/test/java/com/google/adk/web/AdkWebServerStartTest.java`
- `A	dev/src/test/java/com/google/adk/web/InMemoryAppLoaderTest.java`
- `A	dev/src/test/java/com/google/adk/web/controller/AgentControllerTest.java`
- `A	dev/src/test/java/com/google/adk/web/controller/AppGraphControllerTest.java`
- `A	dev/src/test/java/com/google/adk/web/controller/AppGraphTest.java`
- `A	dev/src/test/java/com/google/adk/web/controller/GraphControllerTest.java`
- `A	dev/src/test/java/com/google/adk/web/service/RunnerServiceTest.java`
- `A	dev/src/test/java/com/google/adk/web/testing/GraphFixtures.java`
- `A	dev/src/test/java/com/google/adk/web/testing/StepNode.java`
- `M	examples/a2a_basic/pom.xml`
- `M	examples/a2a_server/pom.xml`
- `M	examples/configagent/pom.xml`
- `M	examples/contextcaching/pom.xml`
- `M	examples/helloworld/pom.xml`
- `M	examples/mcpfilesystem/pom.xml`
- `M	examples/pom.xml`
- `M	examples/spring_chat/pom.xml`
- `M	examples/spring_chat_advanced/pom.xml`
- `M	maven_plugin/examples/custom_tools/pom.xml`
- `M	maven_plugin/examples/simple-agent/pom.xml`
- `M	maven_plugin/pom.xml`
- `M	pom.xml`
- `M	tokt/pom.xml`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/EventCodec.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/LlmResponseCodec.kt`
- `A	tokt/src/main/kotlin/com/google/adk/tokt/codecs/TranscriptionCodec.kt`
- `M	tokt/src/test/kotlin/com/google/adk/tokt/KtRunnerInteropTest.kt`
- `M	tutorials/city-time-weather/pom.xml`
- `M	tutorials/live-audio-single-agent/pom.xml`
