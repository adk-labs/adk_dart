# 2026-10-10 `CascadeLive`, `ElevenLabs`, Skill Telemetry, CLI Triggers & `flutter_adk` Parity Worklog

## Overview
This worklog documents commit `fb5529a` (`2026-10-10`), which synchronized the latest `adk-python` (`c220fca16..15486dbb2`), `adk-go` (`49904c0d..987c7bc0`), `adk-java` (`189d463a`), `adk-kotlin` (`0015305a..89c796cd`), `adk-js` (`22f3bf99..86d1cfef`), and `adk-web` (`9e7aa4c`) upstream changes into `adk_dart`, `packages/adk`, and `packages/flutter_adk`.

---

## 1. `CascadeLive` & `ElevenLabs` Speech Integration (`adk-python` `128faabb6`)
- **`lib/src/live/`**:
  - `cascade_live_events.dart`: `IngressEvent` (`PartialTranscript`, `UserTurnFinished`, `UserSpeechStarted`) and `EgressEvent` (`AudioChunk`, `AgentSpokenOutput`).
  - `transforms.dart`: `CancelSignal`, `LiveIngress`, and `LiveEgress` interfaces.
  - `cascade_live_connection.dart`: `CascadeLiveConnection` bridging streaming STT ingress, text LLM turn generation, tool calls, barge-in interruption (`interrupted: true`), `inputTranscription` / `outputTranscription`, and streaming TTS egress.
  - `cascade_live.dart`: `CascadeLive` model wrapper supporting string model names (resolved via `LLMRegistry.newLlm`) or `BaseLlm` instances.
- **`lib/src/integrations/eleven_labs/eleven_labs.dart`**:
  - Implemented `ElevenLabsSTT` (`LiveIngress`), `ElevenLabsTTS` (`LiveEgress` with sentence boundary chunking and PCM sample rate MIME formatting `audio/pcm;rate=<rate>`), and `ElevenLabsSpeechClient`.
- **Feature Registry & Base Connection**:
  - Registered `FeatureName.cascadeLive` (`CASCADE_LIVE`) and `FeatureName.elevenLabs` (`ELEVEN_LABS`) in `_feature_registry.dart`.
  - Added `sendActivityStart()` and `sendActivityEnd()` on `BaseLlmConnection`.

## 2. Skill Tool Span Naming & Built-in Function Constants (`c11060cca`, `cb6d67997`)
- **`lib/src/telemetry/tracing.dart` & `lib/src/tools/skill_toolset.dart`**:
  - Added `TraceSpanRecord.updateName` and `formatSkillToolSpanName` so `execute_tool` spans for `load_skill`, `load_skill_resource`, and `run_skill_script` are dynamically renamed (`execute_tool load_skill [skill_name]`, etc.) once the skill/resource/script is confirmed non-hallucinated.
- **`lib/src/utils/function_call_names.dart`**:
  - Centralized `requestEucFunctionCallName`, `requestConfirmationFunctionCallName`, `requestInputFunctionCallName`, `transferToAgentFunctionCallName`, and `compactionToolName`.

## 3. Tooling, Models, Sessions & Cross-SDK Fixes
- **`RestApiTool` (`b9308284a`)**: Returns a structured `{error: Missing required path parameter ...}` map instead of throwing when a path parameter is missing or empty.
- **`FunctionTool` (`6a60d6a2e`)**: Preserves callable object metadata and avoids colliding partial tool names.
- **`LiteLlm` (`b158f9f84`) & `ApigeeLlm` (`f5db3104c`)**: Preserves all text parts of assistant messages in `LiteLlm` and retains text sent alongside function responses in `ApigeeLlm`.
- **Concurrent Lazy Init Guard (`15486dbb2`)**: Guarded concurrent `getTools` initialization in `ComputerUseToolset` and `EnvironmentToolset` using a shared initialization future.
- **Cross-SDK (`adk-go`, `adk-java`, `adk-kotlin`, `adk-js`)**:
  - Added `Secret`, `ExperimentalAuthApi`, and `SecretAccess` (`lib/src/auth/secret.dart`).
  - Added `NodeConfig` and `RetryConfig` defaults/validation (`lib/src/workflow/workflow.dart`).
  - Added `beforeRunReplyKey` (`adk:before_run_reply`) preservation in `Runner` and `RemoteA2aAgent`.
  - Added row locking (`FOR UPDATE`) for `app_states` and `user_states` in `NetworkDatabaseSessionService.appendEvent`.
  - Bounded `/run_live` WebSocket message size (`16 MiB` -> `1009`), keepalive ping, and concurrent session limits (`503`), and added `/dev/apps/...` and `/dev/build_graph/...` routes in `web_server.dart`.
  - Added eventarc/pubsub/webhook trigger routes (`packages/adk/lib/src/cli/trigger_routes.dart`).

## 4. `flutter_adk` parity with `adk-web` (`9e7aa4c`)
- Added `AdkCodeExecutionCard` and `AdkGroundingSourcesBar`, and wired `AdkAudioRecordingBar`, `AdkMarkdownText`, `AdkToolConfirmationCard`, and `AdkTraceWaterfallView` with `AdkChatController` and `AdkMessageBubble`.

---

## Verification
- Added `test/oct_09_2026_upstream_parity_test.dart` (626 lines) and expanded `packages/adk/test/cli_test.dart` and `packages/flutter_adk/test/flutter_adk_test.dart`.
