# 2026-05-11 최신 ADK ref 반영

기준 ref:

- `adk-python`: `8788d1c2..0821f2d4`
- `adk-js`: `53ee7eb..3d82451`
- `adk-java`: `9700523e..509c4aa7`

## 작업 단위

### SkillToolset 프롬프트/도구 정렬

- 작업 내용: `SkillToolset`을 명시적인 `skills` 목록 기반으로 정리하고, registry fallback 및 `search_skills` 도구를 제거했다. LLM 요청 전처리도 기본 skill 안내만 추가하고, 정상적인 list tool이 있을 때는 `<available_skills>` XML을 system instruction에 직접 주입하지 않도록 맞췄다.
- 작업 이유: 최신 `adk-python`에서 `skill_registry.py`와 registry 기반 검색 경로가 제거되어, 모델에 노출되는 도구와 system prompt 구성이 달라지면 skill 선택 동작이 Python과 달라질 수 있기 때문이다.

### LlmAgent outputKey 저장 조건

- 작업 내용: final response가 function response만 포함하거나 visible text part가 없으면 `outputKey` 상태 저장을 건너뛰도록 수정했다.
- 작업 이유: tool 실행 후 `skipSummarization`으로 최종 이벤트가 function response 형태가 되는 경우, Python은 사용자에게 보이는 텍스트가 없을 때 상태에 빈 final answer를 쓰지 않는다.

### LlmResponse/session 공통 API 보강

- 작업 내용: `LlmResponse.getFunctionCalls()`, `LlmResponse.getFunctionResponses()` helper와 `BaseSessionService.flush()` no-op hook을 추가했다.
- 작업 이유: 최신 Python/JS 런타임은 response/event helper와 session flush hook을 공통 경로에서 사용하므로, Dart에서도 같은 호출 지점을 제공해야 플로우/플러그인 구현 차이를 줄일 수 있다.

### Gemini EAP 모델 판정

- 작업 내용: `isGeminiEapOr2OrAbove()`를 추가하고 URL Context, Vertex AI RAG retrieval, output schema with tools gating에 적용했다.
- 작업 이유: 최신 ref는 Gemini 2+뿐 아니라 `*-early-exp*` 계열 EAP Gemini 모델도 같은 server-side capability 경로로 처리한다.

### BigQuery analytics agent response 로깅

- 작업 내용: final visible agent text를 `AGENT_RESPONSE` 이벤트로 기록하고, thought/function-call/function-response/long-running-tool 이벤트는 제외하도록 구현했다.
- 작업 이유: 최신 Python BigQuery analytics plugin이 agent 최종 응답을 별도 이벤트로 분석 가능하게 기록하므로, Dart 플러그인의 analytics view/event type도 맞춰야 한다.

### OAuth2 PKCE 메타데이터 보존

- 작업 내용: `OAuth2Auth`에 `nonce`, `codeVerifier`, `codeChallengeMethod`를 추가하고 auth parser, copy, exchange/refresh token 적용, OpenAPI auth normalization, OAuth2 session 구성에서 보존하도록 수정했다.
- 작업 이유: 최신 Python auth flow는 PKCE `S256`과 nonce 기반 OAuth/OpenID Connect 요청을 지원한다. Dart는 실제 token exchange를 handler에 위임하더라도 credential payload가 이 값을 잃으면 동일한 flow를 구현할 수 없다.

### Flutter 예제/문서 최신화

- 작업 내용: Flutter sample의 Skills 예제와 다국어 README에서 registry/search 기반 설명을 제거하고 inline skills 기반 설명으로 정리했다.
- 작업 이유: 최신 Python의 model-facing skill prompt와 tool 구성이 registry 검색을 노출하지 않으므로, Flutter 예제가 오래된 `search_skills` 사용법을 안내하면 실제 런타임 동작과 어긋난다.

### 추가 gap 검토 후 런타임 보정

- 작업 내용: live 모드에서 audio뿐 아니라 image/video inline media 이벤트도 세션 저장에서 제외하고, `Runner.close()`가 session service `flush()`를 호출하도록 맞췄다.
- 작업 이유: 최신 Python `Runner`는 live model media blob을 세션에 직접 저장하지 않고 close 시 session service flush hook을 호출한다. 이 동작이 다르면 live 세션 저장 용량과 buffered session service 종료 동작이 Python과 달라질 수 있다.

### EnvironmentToolset 출력 제한 옵션

- 작업 내용: `EnvironmentToolset(maxOutputChars: ...)` 옵션을 추가하고 `Execute` stdout/stderr 및 `ReadFile` 출력 truncation에 적용했다.
- 작업 이유: 최신 Python 환경 toolset은 호출자가 출력 제한을 조정할 수 있다. Dart가 고정 30000자만 사용하면 긴 출력 제어 동작이 달라진다.

### 캐시 분석 null 처리 정렬

- 작업 내용: cache performance analyzer가 `invocationsUsed == null` 값을 평균/합계에서 제외하고, `cacheName == null` 값은 refresh count에서 제외하도록 수정했다.
- 작업 이유: 최신 Python은 null cache metadata를 0이나 별도 cache refresh로 계산하지 않는다. Dart가 null을 0으로 합산하면 cache 효율 지표가 낮게 계산될 수 있다.

### LLM-backed user simulator 실패 처리

- 작업 내용: simulator LLM이 error code를 반환하거나 thought-only/empty 응답을 반환하면 `noMessageGenerated` 상태 대신 실패 이유가 포함된 `StateError`를 던지도록 수정했다.
- 작업 이유: 최신 Python은 LLM-backed simulator의 빈 응답을 정상 종료 상태로 보지 않고 런타임 오류로 처리한다. 이 차이가 있으면 eval 생성 실패를 조용히 삼키게 된다.

### OAuth2 PKCE challenge method 검증

- 작업 내용: OAuth2 auth request 생성 시 `codeChallengeMethod`가 지정되어 있으면 `S256`만 허용하도록 검증을 추가했다.
- 작업 이유: 최신 Python auth handler는 PKCE에서 `S256` 외 challenge method를 거부한다. Dart는 authorization URL 합성은 하지 않지만 unsupported PKCE payload를 그대로 통과시키지 않도록 공통 검증을 맞췄다.

## 검토 결과

- `adk-js`의 Vertex AI session/memory bank service, Google Maps grounding tool, Vertex tool 계열은 Dart에 이미 대응 구현이 있어 이번 변경에서는 테스트 기준으로 유지했다.
- `adk-java`의 `SkillSource` 계열은 Java SDK의 별도 source abstraction이며, 최신 Python은 registry 검색을 제거했다. Dart는 기존 inline/file skill parsing과 `Skill` 모델을 유지하되 LLM 노출 경로를 Python 기준으로 정리했다.
- `adk-python`의 VMAAS, Firestore integration, CLI onboarding, release/workflow 변경은 Dart 런타임 또는 Flutter example에 직접 매핑되지 않아 별도 구현 대상에서 제외했다.
- 추가 검토에서 `adk-python`의 `agent_engine_sandbox_code_executor.py` 404 재생성 보정은 Python의 Vertex/GenAI client 예외 타입에 묶인 코드 경로라 Dart의 `AgentEngineSandboxClient` 추상화에는 직접 매핑하지 않았다.
- `adk-python`의 `BuiltInCodeExecutor` EAP 모델 판정 변경은 Dart에 동명의 built-in server-side code executor API가 없어 이번 변경에서는 기존 Gemini EAP capability gating 범위만 유지했다.

## 검증

- 통과: `dart test test/skill_toolset_parity_test.dart test/llm_agent_output_state_test.dart test/models_parity_batch2_test.dart test/model_name_utils_parity_test.dart test/tools_extra_batch2_test.dart test/retrieval_tools_parity_test.dart test/utils_content_variant_output_schema_test.dart test/session_service_test.dart test/auth_oauth_discovery_parity_test.dart test/auth_handler_test.dart test/bigquery_agent_analytics_plugin_parity_test.dart`
- 통과: `dart analyze lib test` (error/warning 없음, 기존 info lint만 남음)
- 통과: `flutter analyze` / `flutter test` in `packages/flutter_adk`
- 통과: `flutter analyze` / `flutter test` in `packages/flutter_adk/example`
- 통과: `dart test test/runner_live_config_test.dart test/environment_toolset_parity_test.dart test/utils_missing_parity_test.dart test/user_simulation_parity_test.dart test/auth_handler_test.dart`
- 참고: 루트 전체 `dart test`는 `test/dev_web_server_test.dart`의 기존 dev-server 통합 테스트 2건이 단독 실행에서도 실패했다. 이번 최신화 변경 범위의 auth/skill/analytics/model/session 테스트는 모두 통과했다.
