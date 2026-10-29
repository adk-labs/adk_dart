# ADK Java Daily Change Report

- Date (UTC): 2026-10-29
- Source: `google/adk-java`
- Latest SHA: `7391fa836e8896787eb3f690875152f9f84bcec3`
- Previous SHA: `b7f45e2b54c5331c847e6ceb26ed24f09f8d13ee`

## Summary

- New commits: 5

## Commits

- [7391fa83](https://github.com/google/adk-java/commit/7391fa836e8896787eb3f690875152f9f84bcec3) feat: add a Spring Boot chat that streams replies and mixes ADK and Spring AI tools (Rafal Glowinski, 2026-10-29)
- [2e8dbead](https://github.com/google/adk-java/commit/2e8dbeada175adebab13f49bdc6cafe24ecd7341) feat: add App.toBuilder() (Damian Osadczuk, 2026-10-29)
- [528a99d4](https://github.com/google/adk-java/commit/528a99d4d79c73f5f654d7f0f7777b41e32fd46c) feat: run a node once per item of a list input (Miłosz Sobczyk, 2026-10-29)
- [bca05915](https://github.com/google/adk-java/commit/bca05915b244cfc23bfd738c4feadc2ae5f53f58) feat: add a Spring Boot chat app backed by an ADK agent (Rafal Glowinski, 2026-10-29)
- [c2ab2e32](https://github.com/google/adk-java/commit/c2ab2e3225c81b41897f5678f97d1eaca6b92ad9) fix: keep event isolation scopes in an adapted Java session service (Damian Momot, 2026-10-28)

## Changed Files

- `M	core/src/main/java/com/google/adk/apps/App.java`
- `A	core/src/main/java/com/google/adk/workflow/ParallelWorkers.java`
- `M	core/src/test/java/com/google/adk/apps/AppTest.java`
- `A	core/src/test/java/com/google/adk/workflow/ParallelWorkersTest.java`
- `M	examples/README.md`
- `M	examples/pom.xml`
- `A	examples/spring_chat/README.md`
- `A	examples/spring_chat/pom.xml`
- `A	examples/spring_chat/src/main/java/com/example/springchat/AgentConfig.java`
- `A	examples/spring_chat/src/main/java/com/example/springchat/ChatController.java`
- `A	examples/spring_chat/src/main/java/com/example/springchat/SpringChatApplication.java`
- `A	examples/spring_chat/src/main/resources/application.properties`
- `A	examples/spring_chat/src/main/resources/static/index.html`
- `A	examples/spring_chat_advanced/README.md`
- `A	examples/spring_chat_advanced/pom.xml`
- `A	examples/spring_chat_advanced/src/main/java/com/example/springchat/advanced/AgentConfig.java`
- `A	examples/spring_chat_advanced/src/main/java/com/example/springchat/advanced/ChatController.java`
- `A	examples/spring_chat_advanced/src/main/java/com/example/springchat/advanced/OrderService.java`
- `A	examples/spring_chat_advanced/src/main/java/com/example/springchat/advanced/ShippingTools.java`
- `A	examples/spring_chat_advanced/src/main/java/com/example/springchat/advanced/SpringChatAdvancedApplication.java`
- `A	examples/spring_chat_advanced/src/main/resources/application.properties`
- `A	examples/spring_chat_advanced/src/main/resources/static/index.html`
- `M	pom.xml`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/JavaAdkToKt.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/EventCodec.kt`
- `M	tokt/src/test/kotlin/com/google/adk/tokt/KtRunnerInteropTest.kt`
