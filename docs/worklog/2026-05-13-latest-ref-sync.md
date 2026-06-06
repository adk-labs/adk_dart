# 2026-05-13 최신 ADK ref 반영

기준 ref:

- `adk-go`: `ae7aed4..853c11b`
- `adk-python`: `218ea76e..fd8b4929`
- `adk-js`: `fc1ff1f` 이후 변경 없음
- `adk-java`: `d837ef0` 이후 변경 없음
- `adk-web`: `51a50c7..dfcd354`

## 작업 단위

### Go telemetry reasoning token 정렬

- 작업 내용: reasoning token이 있을 때 output token span attribute가 `candidatesTokenCount + thoughtsTokenCount`를 기록하도록 맞추고, semantic convention attribute를 `gen_ai.usage.reasoning.output_tokens`로 갱신했다.
- 작업 이유: 최신 Go telemetry는 reasoning output token을 별도 attribute로 내보내면서 output token 합계에도 포함한다. Dart trace가 이전 experimental key만 쓰면 token accounting이 Go와 달라진다.

### Go streaming thought signature 정렬

- 작업 내용: progressive SSE aggregation 중 thought part의 `thoughtSignature`를 기억했다가 바로 이어지는 첫 function call part에 복사하도록 수정했다.
- 작업 이유: 최신 Go는 streaming thought signature가 function call로 이어지는 경우 tool call provenance를 잃지 않도록 보존한다.

### Go parallel HITL 회귀 테스트 포팅

- 작업 내용: parallel function call 두 개가 동시에 confirmation을 요구하는 흐름과, resume 시 확인된 call만 실행되는 흐름을 Dart flow processor 테스트에 추가했다.
- 작업 이유: 최신 Go가 추가한 parallel HITL regression을 Dart에서도 유지해야 장기 실행/확인 기반 tool call resume 동작이 깨지는 것을 잡을 수 있다.

### Python Skill Registry 재반영

- 작업 내용: `SkillToolset`에 optional `SkillRegistry` fallback, per-invocation fetch cache, `search_skills` tool, registry search guidance를 추가했다.
- 작업 이유: 최신 Python이 registry 기반 skill discovery를 다시 추가했다. Dart가 local skill만 노출하면 remote/dynamic skill discovery와 activated additional tool 해석이 Python과 달라진다.

### Python Anthropic tool_use ID 보존

- 작업 내용: Anthropic request serialization에서 valid tool id를 보존하고, invalid/empty id는 request-scoped sanitizer로 deterministic fallback id에 매핑한다. Anthropic session replay에서는 function call/response id를 제거하지 않는다.
- 작업 이유: 최신 Python은 Anthropic session resume 중 `tool_use`와 `tool_result` id mismatch로 API 오류가 나는 경로를 막았다. Dart도 같은 request 안의 invalid paired ids가 동일 fallback으로 바뀌도록 맞췄다.

### Python CacheMetadata invariant 정렬

- 작업 내용: `CacheMetadata`가 active cache일 때 `cacheName`, `expireTime`, `invocationsUsed`를 모두 요구하고, fingerprint-only 상태에서는 셋 모두 null이 되도록 검증한다. legacy map coercion 경로는 partial active metadata를 무시하도록 방어했다.
- 작업 이유: 최신 Python은 partial active cache metadata를 유효 상태로 보지 않는다. Dart가 `expireTime` 없는 active cache를 허용하면 cache reuse/expiry 판단이 불명확해진다.

### Python live transfer resumption handle 정렬

- 작업 내용: live function call 후 agent transfer가 발생하면 child live agent 실행 컨텍스트에서 parent `liveSessionResumptionHandle`과 runConfig session resumption handle을 제거한다.
- 작업 이유: 최신 Python은 child live agent가 parent live session handle을 재사용하지 않도록 수정했다. 같은 handle을 넘기면 child conversation이 parent session을 끊거나 덮을 수 있다.

### 최신 ref 검토 후 제외

- `adk-python`의 A2A persistent task store는 Python FastAPI/a2a-sdk task store URI wiring에 묶인 변경이다. Dart dev server는 자체 in-memory task map과 SQLite-backed push delivery queue를 사용하므로 이번 작업에서는 직접 포팅하지 않았다.
- `adk-python`의 Gemini auto review CI workflow는 Dart 런타임/API 동작에 직접 매핑되지 않아 보고서/state만 반영했다.
- `adk-web` 변경은 web UI의 thought rendering과 chat feature flag 조정으로, Dart SDK/Flutter package 런타임 표면에 직접 적용할 코드가 없었다.
- `adk-js`, `adk-java`는 2026-05-13 확인 기준 새 commit이 없었다.

## 검증

- 통과: `dart test test/skill_toolset_parity_test.dart`
- 통과: `dart test test/models_parity_batch2_test.dart`
- 통과: `dart test test/llm_flow_live_modules_parity_test.dart`
- 통과: `dart test test/utils_missing_parity_test.dart`
- 통과: `dart test test/flow_processors_parity_test.dart` (기존 Vertex 조건 테스트 1건 skip)
- 통과: `dart test test/features_telemetry_parity_test.dart`
- 통과: `dart test test/contents_live_session_parity_test.dart`
- 통과: `dart analyze lib test` (error/warning 없음, 기존 info lint만 남음)
