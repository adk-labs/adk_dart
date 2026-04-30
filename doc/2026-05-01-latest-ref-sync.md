# 2026-05-01 최신 ADK ref 반영

기준 ref:

- `adk-python`: `c87ee1ee..8788d1c2`
- `adk-js`: `220d75b..53ee7eb`
- `adk-java`: `52323b44..9700523e`

## 작업 단위

### Skill registry 연동

- 작업 내용: `SkillRegistry`에 비동기 `getSkill`, `searchSkills`, `getFilterSchema`, `getSearchDescription` contract를 추가하고, `SkillToolset`이 registry 기반 `search_skills` 도구와 동적 `load_skill` fallback을 제공하도록 반영했다.
- 작업 이유: `adk-python`에 새로 추가된 registry 기반 skill discovery/load 흐름과 Dart 런타임의 skill 동작을 맞추기 위해서다.

### Remote A2A 사용자 입력 메타데이터

- 작업 내용: Remote A2A 요청 구성 시 user 이벤트에서 변환된 A2A part에 `is_user_input: true` 메타데이터를 부여한다.
- 작업 이유: 최신 `adk-python`이 remote A2A에서 user-origin part를 명시해 downstream A2A agent가 사용자 입력과 컨텍스트를 구분할 수 있게 변경했기 때문이다.

### Gemini live tool-call 응답 메타데이터

- 작업 내용: Gemini live session의 tool-call 응답에 `modelVersion`을 포함하도록 보강했다.
- 작업 이유: Gemini 3.1 live tool-call 응답을 즉시 방출하는 Python 동작과 메타데이터 전달을 맞추기 위해서다. Dart는 이미 tool-call을 즉시 방출하고 있었으므로 누락된 model version 전달만 보완했다.

### Streaming aggregator final chunk 처리

- 작업 내용: non-progressive streaming aggregation에서 마지막 빈 chunk가 도착해도 이전 chunk의 `finishReason`을 유지하도록 수정했다.
- 작업 이유: 최신 `adk-js`가 Gemini의 trailing empty chunk에서 누적 응답을 버리거나 종료 사유를 잃지 않도록 보정한 것과 같은 동작을 Dart에 반영하기 위해서다.

### LlmAgent output schema 문서 정정

- 작업 내용: `outputSchema`가 tool 사용을 막는 것이 아니라 thought loop 중 tools를 노출하고 final output에 구조를 강제한다는 주석을 반영했다.
- 작업 이유: 최신 `adk-python`의 output schema 설명 변경과 Dart API 문서 의미를 맞추기 위해서다.

## 검토 결과

- `adk-js`의 `url_context`, `vertex_ai_search`, model-id check bypass, MCP tool prefix/filter, built-in retrieval 계열은 Dart에 기존 구현이 있어 추가 구현 대상에서 제외했다.
- `adk-python`의 CLI onboarding/sample-only 변경은 Dart 런타임 동작과 직접 매핑되지 않아 이번 구현 범위에서 제외했다.
- `adk-java`의 Chat Completions request 확장과 Agent Engine deployer는 Java SDK 전용 API 변화로 판단했고, Dart 런타임 parity 구현 대상은 아니었다.
