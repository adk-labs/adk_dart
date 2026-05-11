# 2026-05-01 최신 ADK ref 반영

기준 ref:

- `adk-python`: `c87ee1ee..8788d1c2`
- `adk-js`: `220d75b..53ee7eb`
- `adk-java`: `52323b44..9700523e`

## 작업 단위

### Skill registry 연동

- 작업 내용: 당시 기준으로 `SkillRegistry`에 비동기 `getSkill`, `searchSkills`, `getFilterSchema`, `getSearchDescription` contract를 추가하고, `SkillToolset`이 registry 기반 `search_skills` 도구와 동적 `load_skill` fallback을 제공하도록 반영했다.
- 작업 이유: 2026-05-01 기준 `adk-python`에 새로 추가된 registry 기반 skill discovery/load 흐름과 Dart 런타임의 skill 동작을 맞추기 위해서였다.
- 최신 상태: 2026-05-11 기준 `adk-python`에서 registry 검색 경로가 제거되어, Dart도 `search_skills`와 registry fallback을 제거했다. 최신 문서는 `doc/2026-05-11-latest-ref-sync.md`를 기준으로 한다.

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

### Vertex AI RAG built-in tool 주입

- 작업 내용: `VertexAiRagRetrieval`이 Gemini 2+에서 label metadata 대신 `retrieval.vertexRagStore` built-in tool config를 주입하도록 변경했고, `adk-js`의 새 `VertexRagRetrievalTool` API를 추가했다.
- 작업 이유: 최신 `adk-python`은 Vertex RAG를 model-side retrieval tool로 직접 전달하고, 최신 `adk-js`도 같은 server-side tool 클래스를 제공하므로 Dart의 실제 요청 payload를 맞추기 위해서다.

### AgentTool schema/forwarding 보강

- 작업 내용: `AgentTool`이 child agent의 `inputSchema`를 function declaration에 반영하고, schema 입력은 JSON payload로 전달하며, `outputSchema`가 있으면 child 응답 JSON을 구조화된 객체로 반환하도록 보강했다. Artifact 접근은 parent `ToolContext`를 통해 forwarding한다.
- 작업 이유: Python/JS `AgentTool`은 schema-aware 입출력과 forwarding artifact service를 사용하므로, nested agent를 tool로 호출할 때 선언과 반환 타입이 동일하게 동작해야 한다.

### Telemetry semantic convention key 정렬

- 작업 내용: experimental GenAI semconv fallback key를 `gen_ai.tool_definitions`에서 `gen_ai.tool.definitions`로 변경했다.
- 작업 이유: 최신 `adk-python`의 OpenTelemetry fallback constant가 dotted key로 변경되어, semconv package 미제공 환경에서도 동일한 span attribute를 남기기 위해서다.

## 검토 결과

- `adk-js`의 `url_context`, `vertex_ai_search`, model-id check bypass, MCP tool prefix/filter 계열은 Dart에 기존 구현이 있어 추가 구현 대상에서 제외했다.
- `adk-python`의 CLI onboarding/sample-only 변경은 Dart 런타임 동작과 직접 매핑되지 않아 이번 구현 범위에서 제외했다.
- `adk-python`의 Agent Identity `GcpAuthProvider`는 Dart에 아직 IAM Connector Credentials 클라이언트가 없어 placeholder로 남아 있다. 외부 Google Cloud IAM Connector 의존성과 auth flow 설계가 필요하므로 별도 작업 단위로 분리하는 것이 안전하다.
- `adk-java`의 Chat Completions request 확장과 Agent Engine deployer는 Java SDK 전용 API 변화로 판단했고, Dart 런타임 parity 구현 대상은 아니었다.
