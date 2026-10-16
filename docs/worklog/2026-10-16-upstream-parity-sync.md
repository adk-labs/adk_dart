# Upstream Multi-SDK Parity Sync & Enhancements (2026-10-16)

## Overview
Comprehensive synchronization across all upstream ADK repositories (`adk-python`, `adk-go`, `adk-java`, `adk-js`, `adk-kotlin`, `adk-web`) bringing `adk_dart` and `packages/adk` to complete parity.

---

## Unit 1: Core Runtime Updates
- **BaseAgent Artifact Delta Recording (`019387c62`)**:
  - In `lib/src/agents/base_agent.dart`: Updated callback event generation so `actions.artifactDelta` from `beforeAgentCallback` and `afterAgentCallback` produces an `Event` even when `state.hasDelta()` is false.
- **AgentTool RunConfig Forwarding (`6ed5dd08`)**:
  - In `lib/src/tools/agent_tool.dart`: Forwarded `runConfig: invocationContext.runConfig` when invoking `runner.runAsync(...)`, ensuring the model-call budget (`maxLlmCalls`) and runtime configuration bound sub-agent executions identically to the caller.
- **Memory Service `deleteMemory` API (`41e5c7b90`, `2416f660b`)**:
  - `BaseMemoryService`: Added `Future<void> deleteMemory({required String appName, required String userId, String? memoryId})`.
  - `InMemoryMemoryService`: Added `_deletedMemoryIdsByUserKey` tracking to purge deleted events and prevent re-ingestion from subsequent session additions. Added `id: event.id` to `MemoryEntry`.
  - `InvocationContext` and `Context`: Added `deleteMemory({String? memoryId})` delegation.
- **JSON Pointer `$ref` Dereferencing (`59fe93bd0`)**:
  - `lib/src/tools/_gemini_schema_util.dart`: Implemented `_resolveJsonPointer` with URI-fragment parsing, URI unquoting, token unescaping (`~1` -> `/`, `~0` -> `~`), array indexing, supporting both `definitions` and `$defs`, circular reference detection, and defs fallback.
- **Tests**:
  - Added [test/unit1_core_parity_test.dart](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/test/unit1_core_parity_test.dart) covering JSON Pointer resolution and `InMemoryMemoryService.deleteMemory`.

---

## Unit 2: Live Ingress/Egress Models (`GeminiSTT` & `GeminiTTS`)
- **`GeminiSTT` Ingress Transform (`f78149a97`, `_gemini_stt.py`)**:
  - Created `lib/src/live/gemini_stt.dart` implementing `LiveIngress` (`Stream<InlineData> audio` -> `Stream<IngressEvent>`).
  - Added `_AudioBuffer` with `maxReplayMs` capping (default 10,000ms, 16kHz 16-bit mono) to preserve speech during session transitions.
  - Connects to Gemini Live API (`gemini-3.5-transcribe-live`) using `LiveConnectConfig(responseModalities: ['TEXT'], speechConfig: {'silenceDurationMs': silenceDurationMs, ...})`.
  - Dispatches `UserSpeechStarted`, `PartialTranscript`, and `UserTurnFinished` events upon transcription and turn completion (`resp.turnComplete == true`).
- **`GeminiTTS` Egress Transform (`f78149a97`, `_gemini_tts.py`)**:
  - Created `lib/src/live/gemini_tts.dart` implementing `LiveEgress` (`Stream<String> text` with `CancelSignal cancel` -> `Stream<EgressEvent>`).
  - Implemented sentence boundary regex `_sentenceEnd` and CJK clause detection `_cjkClauseEnd` with `minSegmentChars` (default 50) and `maxSegmentChars` (default 240) to synthesize natural audio chunks.
  - Generates `AudioChunk` blobs from model `Part.inlineData` and records `AgentSpokenOutput` text once audio synthesis completes.
  - Supports immediate cancellation and barge-in via `CancelSignal`.
- **`GenerateContentConfig` Modality & Speech Additions**:
  - Added `responseModalities` and `speechConfig` to `GenerateContentConfig` in `lib/src/models/llm_request.dart`, with overrides in `AnthropicGenerateContentConfig` in `lib/src/models/anthropic_llm.dart`.
  - Updated `_buildGenerationConfig` in `lib/src/models/google_llm.dart` to serialize `responseModalities` and `speechConfig`.
- **Exports**:
  - Exported `GeminiSTT` and `GeminiTTS` in `lib/src/live/live.dart`, which is re-exported by `lib/adk_dart.dart` and `lib/adk_core.dart`.
- **Tests**:
  - Added [test/unit2_gemini_speech_test.dart](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/test/unit2_gemini_speech_test.dart) covering `GeminiTTS` synthesis, segment splitting, barge-in cancellation, constructor validations, and `GeminiSTT` audio streaming and transcription events (100% pass).

