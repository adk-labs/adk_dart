# 2026-05-16 최신 ADK ref 반영

기준 ref:

- `adk-python`: `fd8b4929..bd062ec9`
- `adk-java`: `d837ef0..3e496e4`
- `adk-js`: `fc1ff1f` 이후 변경 없음
- `adk-go`, `adk-web`: ref sync 스크립트에서 local changes로 skipped

## 작업 단위

### A2A input/auth-required resume

- 작업 내용: non-ADK A2A peer가 `input_required` 또는 `auth_required` 상태를 반환했지만 ADK long-running tool id가 없을 때, 마지막 text part를 synthetic function call인 `mock_function_call_for_required_user_input`으로 변환하고 long-running id를 부여했다. 사용자가 이 mock function response를 보내면 RemoteA2A request는 data part가 아니라 일반 text message로 재개되도록 처리했다.
- 작업 이유: 최신 Python은 ADK가 만들지 않은 A2A input-required 이벤트도 사용자가 응답해 이어갈 수 있게 한다. Dart가 text 그대로만 보존하면 runner가 resume 가능한 long-running interaction으로 인식하지 못한다.

### AgentTool code result 병합

- 작업 내용: `AgentTool`의 child agent 결과 병합에서 text뿐 아니라 `codeExecutionResult.output/result`와 `executableCode.code`도 최종 tool result 문자열에 포함하도록 확장했다.
- 작업 이유: 최신 Python은 code execution agent를 tool로 감쌌을 때 stdout이나 실행 코드가 사라지는 문제를 수정했다. Dart도 code execution 결과를 parent agent가 볼 수 있어야 한다.

### Gemini empty response 처리

- 작업 내용: Gemini REST 응답에 candidates가 없고 prompt feedback도 없으면 error가 아니라 빈 model content를 가진 성공 응답으로 반환하도록 바꿨다.
- 작업 이유: 최신 Python은 blocked prompt가 아닌 빈 GenerateContentResponse를 정상 응답으로 취급한다. Dart가 `UNKNOWN_ERROR`로 바꾸면 retry/error handling이 Python과 달라진다.

### output_key state visibility

- 작업 내용: Runner가 user/model/output/buffered event를 append할 때 로컬 session 인자가 아니라 최신 `InvocationContext.session`을 사용하도록 정렬했다. after-run callback에서 `outputKey` state delta가 즉시 보이는 회귀 테스트를 추가했다.
- 작업 이유: 최신 Python은 `output_key` state delta가 callbacks/plugins에서 보이지 않던 문제를 고쳤다. Dart도 session state mutation이 같은 invocation context에 반영되어야 한다.

### HITL-safe compaction

- 작업 내용: token-threshold 및 sliding-window compaction 후보에서 unresolved function call뿐 아니라 unresolved human-in-the-loop confirmation/auth 요청 이벤트 앞까지만 compact하도록 보강했다.
- 작업 이유: 최신 Python은 HITL 요청/응답 쌍이 compaction으로 잘려 resume이 깨지는 문제를 막았다. Dart도 approval/auth 대기 이벤트는 history에 남겨야 한다.

### Interactions/Anthropic tool result 직렬화

- 작업 내용: Interactions API 변환에서 map/list/string function result를 미리 JSON 문자열화하지 않도록 수정했다. Anthropic tool result에서는 `response.content`가 string이면 그대로 plain content로 유지한다.
- 작업 이유: 최신 Python은 Interactions API dict double-escaping과 Anthropic string tool_result JSON wrapping 문제를 수정했다. Dart도 tool result schema와 provider payload를 동일하게 유지해야 한다.

### Evaluation live mode와 multimodal eval event

- 작업 내용: `InferenceConfig`에 live inference 옵션과 timeout을 추가하고, `LocalEvalService`에서 `Runner.runLive` 기반 inference 경로를 지원했다. eval invocation 변환은 intermediate event의 inline data/file data를 보존하도록 확장했다.
- 작업 이유: 최신 Python은 ADK evaluate에서 Gemini Live API 실행을 지원하고, eval trajectory에 multimodal intermediate data를 남긴다. Dart eval도 같은 데이터 손실 없이 기록해야 한다.

### Google Cloud telemetry mTLS

- 작업 내용: Cloud Trace exporter endpoint 선택에 `GOOGLE_API_USE_MTLS_ENDPOINT`와 `GOOGLE_API_USE_CLIENT_CERTIFICATE` 규칙을 반영했다.
- 작업 이유: 최신 Python telemetry는 Google API mTLS endpoint 선택 규칙을 따른다. Dart exporter도 동일한 환경 변수 동작을 제공해야 한다.

### SkillToolset cache/description 정렬

- 작업 내용: SkillToolset의 fetched skill cache 명칭과 close-time cache clear/child toolset close 동작을 정리했다. skill frontmatter description 길이 초과 오류에는 실제 길이를 포함하도록 했다.
- 작업 이유: 최신 Python은 dynamic skill fetch cache와 BaseToolset cache 혼동을 줄이고, validation error를 디버깅 가능하게 바꿨다.

## 최신 ref 검토 후 제외

- Python `GCPSkillRegistry`는 Vertex AI Skill Registry API 클라이언트와 인증/리소스 스키마가 필요한 별도 통합이다. Dart에는 이미 local/in-memory/GCS skill registry 표면이 있고, 이번 작업에서는 런타임 parity에 직접 필요한 SkillToolset cache/activation 경로만 반영했다.
- Python MCP AnyIO CancelScope 변경은 Python async runtime의 task boundary 문제에 대한 수정이다. Dart MCP session manager는 AnyIO를 사용하지 않아 직접 포팅 대상이 아니다.
- Python lazy-load service registry/app split, CLI flag 제거, Gemini Actions workflow 변경은 Python 패키징/CI/cold-start 구조 변경이다. Dart SDK 런타임 동작에 직접 매핑되는 코드 변경은 없었다.
- Java `ChatCompletionsHttpClient`는 Java 전용 HTTP client 추가다. Dart는 이미 REST transport 기반 Gemini/Apigee-compatible non-streaming 경로를 갖고 있어 별도 Java-only class 포팅은 하지 않았다.
- JS는 2026-05-16 확인 기준 이전 state(`fc1ff1f`) 이후 새 main commit이 없었다.

## 검증

- 통과: `dart test test/a2a_parity_test.dart test/remote_a2a_agent_parity_test.dart test/agent_tool_test.dart test/google_llm_rest_test.dart test/compaction_parity_test.dart test/skill_toolset_parity_test.dart test/interactions_utils_parity_test.dart test/models_parity_batch2_test.dart test/evaluation_generator_parity_test.dart test/local_eval_service_test.dart test/features_telemetry_parity_test.dart test/llm_agent_output_state_test.dart`
- 통과: `dart test test/a2a_parity_test.dart test/google_llm_rest_test.dart`
- 통과: `dart analyze lib test` (error/warning 없음, 기존 info lint만 남음)
