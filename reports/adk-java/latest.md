# ADK Java Daily Change Report

- Date (UTC): 2026-11-03
- Source: `google/adk-java`
- Latest SHA: `d100738a62cf5ebf631ba9a6c288406cd999eb79`
- Previous SHA: `30edd998914c6412276d1b9c4b72dcdfb9f97976`

## Summary

- New commits: 5

## Commits

- [d100738a](https://github.com/google/adk-java/commit/d100738a62cf5ebf631ba9a6c288406cd999eb79) feat(workflow): add JoinNode.create for a join that needs only a name (Damian Momot, 2026-11-03)
- [3582f1a6](https://github.com/google/adk-java/commit/3582f1a688eff82aeff5fec2eb2191a7acb0cd11) feat(tokt): run agents through the ADK Java runner's runLive (Kamil Tomaszek, 2026-11-03)
- [e4f762c3](https://github.com/google/adk-java/commit/e4f762c3be550954dea6494e1c0a32fbd4437e74) refactor(tokt): convert an ADK Java RunConfig for a live run (Kamil Tomaszek, 2026-11-03)
- [ab346177](https://github.com/google/adk-java/commit/ab34617775820fc67dcec423711fe8674353e23b) feat(tokt): convert speech and transcription configs (Kamil Tomaszek, 2026-11-03)
- [0bb7f4ac](https://github.com/google/adk-java/commit/0bb7f4acfa84848722108547c08d2a97bfc4450d) fix(tokt): merge a Java plugin's replacement onto the original, as ADK Python does (Kamil Tomaszek, 2026-11-02)

## Changed Files

- `M	core/src/main/java/com/google/adk/workflow/JoinNode.java`
- `M	core/src/test/java/com/google/adk/workflow/JoinNodeTest.java`
- `M	tokt/README.md`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/KotlinAdkToJava.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/KtRunnerToJava.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/adapters/JavaPluginToKt.kt`
- `A	tokt/src/main/kotlin/com/google/adk/tokt/codecs/AudioTranscriptionConfigCodec.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/EventCodec.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/LlmResponseCodec.kt`
- `M	tokt/src/main/kotlin/com/google/adk/tokt/codecs/RunConfigCodec.kt`
- `A	tokt/src/main/kotlin/com/google/adk/tokt/codecs/SpeechConfigCodec.kt`
- `M	tokt/src/test/kotlin/com/google/adk/tokt/KtRunnerInteropTest.kt`
