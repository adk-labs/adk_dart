# 2026-05-24 Latest Ref Sync

## 기준

- `adk-python`: `6e0c1e59181cf104a11ef820dd45a289efc24ea6` -> `7ad7994744de18f2394e4bcb961cd5c7a24afb4b`
- `adk-java`: `b4791ef362840e79d008221f272992532c4732cd` -> `5ee51fd1f3ecd9445fa559ee66fe426df7008ea8`
- `adk-js`: 변경 없음
- `adk-go`: ref clone에 로컬 변경/비정상 state가 있어 이번 추적 SHA 갱신에서 제외

## 작업 단위

### 1. Gemini live transcription flush

- 작업 내용: Gemini live connection에서 `interrupted`, `turnComplete`, `generationComplete` 발생 시 Gemini API뿐 아니라 Vertex AI backend도 pending input/output transcription을 flush하도록 수정했다.
- 작업 이유: Python `d17a2a32`에서 Gemini v3.1/Vertex AI가 finished signal을 보내지 않는 경우를 보정했다. Dart도 backend에 관계없이 동일하게 최종 transcription event를 만들어야 한다.

### 2. Grounding-only live response 보존

- 작업 내용: `BaseLlmFlow`의 live/async postprocess skip 조건에 `groundingMetadata`를 포함해, content가 없고 grounding metadata만 있는 응답도 event로 남기도록 수정했다.
- 작업 이유: Python `b9751eb9`와 동일하게 Gemini 3.1 live에서 grounding metadata-only packet이 유실되면 검색/grounding 결과가 UI와 최종 응답에 반영되지 않는다.

### 3. Environment EditFileTool CRLF/regex 처리

- 작업 내용: `EditFile`의 `old_string` 매칭을 CRLF/LF 모두 허용하도록 바꾸고, regex metacharacter를 literal로 escape한 뒤 첫 1회만 치환하도록 수정했다.
- 작업 이유: Python `1f245535`와 동일하게 Windows/Unix 줄바꿈 차이와 `[]`, `.`, `+`, `$` 같은 문자가 포함된 파일 편집 실패를 줄인다.

### 4. MCP session startup error observation

- 작업 내용: `SessionContext.start()`의 background startup future에 `ignore()` observer를 붙여 호출자가 시작 future를 버린 경우에도 startup exception이 미처리 오류로 남지 않도록 했다.
- 작업 이유: Python `933653c6`는 MCP background task exception을 회수해 live stream 비정상 종료를 방지한다. Dart는 구조가 다르지만 같은 실패 모드를 줄이는 방향으로 반영했다.

### 5. Tool error telemetry

- 작업 내용: `traceToolCall`에 `errorType` 인자를 추가하고, `BaseTool.detectErrorInResponse()` / `FunctionTool.detectErrorInResponse()` hook을 추가했다.
- 작업 이유: Python `e56c021e`처럼 tool이 exception을 던지지 않고 `{error: ...}` payload를 반환해도 telemetry에서 `error.type=TOOL_ERROR`로 기록할 수 있어야 한다.

### 6. user.id telemetry log-only 처리

- 작업 내용: inference span 공통 attribute에서 `user.id`를 제거하고, prompt/user message log 및 experimental operation details event에만 포함되도록 분리했다. 외부 Google GenAI instrumentation path도 일반 extra attribute와 event-only attribute를 분리했다.
- 작업 이유: Python `eb379bea`와 동일하게 span에는 user identifier를 직접 노출하지 않고, content capture가 켜진 log/event 경로에만 user attribution을 넣는다.

### 7. 최신 ref 리포트 갱신

- 작업 내용: `reports/adk-python/2026-05-24.md`, `reports/adk-java/2026-05-24.md`, `reports/adk-js/2026-05-24.md`를 추가하고 latest/state 파일을 갱신했다.
- 작업 이유: 최신화 기준 SHA를 명확히 남겨 다음 sync 때 누락/중복 반영을 줄인다.

## 이번 작업에서 남긴 Gap

- Python v2 workflow/node runtime은 `src/google/adk/workflow/*` 전체 신규 아키텍처라 단순 parity patch가 아니라 별도 설계/포팅 단위가 필요하다.
- Python `adk web`의 `api_server.py`, `dev_server.py`, 브라우저 asset 대량 변경은 Dart dev server 구조와 직접 1:1 매핑되지 않아 별도 UI/server parity 검토가 필요하다.
- Python sample tree 대규모 재배치와 `.agents/skills/*` 문서 추가는 Dart package runtime에는 직접 영향이 적어 이번 코드 커밋에서는 문서 gap으로만 추적했다.
- Java ChatCompletions streaming client, SkillSource toolset, GCS offloader는 Dart에 대응 API 설계가 필요해 별도 작업으로 남겼다.

## 검증

- `dart analyze lib test`
- `dart test test/environment_toolset_parity_test.dart test/models_parity_batch2_test.dart test/llm_flow_live_modules_parity_test.dart test/features_telemetry_parity_test.dart test/tools_batch2_parity_test.dart`
- `dart test`는 전체 스위트에서 실패했다. 별도 재현 시 `test/dev_web_server_test.dart`의 기존 2건(`dynamic file-path class spec` 400 응답, persisted A2A push retry callback 미발생)이 계속 실패했다. full run 중 보인 `cli_built_in_agents_assets_test.dart` asset missing 3건은 해당 파일 단독 재실행에서는 재현되지 않았다.
