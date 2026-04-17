# 2026-04-17 adk-python latest sync

기준 upstream:
- `ref/adk-python`
- range: `23bd95bc..fe48d875`

이번 배치는 upstream 전체 diff를 그대로 기계적으로 옮기지 않고, `adk_dart` 현재 구조에 직접 대응 가능한 runtime/API parity 항목만 선별해서 반영했다.

## 작업 단위 1. Skill toolset 인자/응답 표준화

작업 내용
- `load_skill` 기본 인자를 `name`에서 `skill_name`으로 정규화했다.
- `load_skill_resource` 기본 인자를 `path`에서 `file_path`로 정규화했다.
- `run_skill_script` 기본 인자를 `script_path`에서 `file_path`로 정규화했다.
- `run_skill_script.args`가 `Map`뿐 아니라 `List`도 받도록 확장했다.
- `args`가 리스트일 때 `short_options`/`positional_args`를 같이 받으면 `INVALID_ARGUMENTS`로 거절하도록 맞췄다.
- binary resource 안내 문구와 응답 payload를 upstream 기준(`file_path`, injected-content message)으로 맞췄다.
- 기존 호출 호환성을 위해 `name`, `path`, `script_path` alias는 런타임에서 계속 허용했다.

작업 이유
- upstream `skill_toolset`이 툴 선언 스키마와 런타임 인자명을 `skill_name` / `file_path` 중심으로 정리했다.
- 현재 Dart 구현은 구버전 인자명과 에러 코드를 유지하고 있어서 모델이 최신 Python 문서/프롬프트를 따라 호출하면 불일치가 생길 수 있었다.
- alias를 남겨야 기존 Dart 호출자와 저장된 대화 히스토리를 깨지 않고 parity를 올릴 수 있다.

## 작업 단위 2. `live_session_id` 전파/저장 parity

작업 내용
- `LlmResponse`, `Event`에 `liveSessionId` 필드를 추가했다.
- `BaseLlmFlow`가 모델 응답의 `liveSessionId`를 최종 이벤트로 전파하도록 수정했다.
- `GeminiLlmConnection` live 경로에서 생성하는 usage/content/transcription/turn-complete/interrupted 응답에 `liveSessionId`를 싣도록 맞췄다.
- session schema v0/v1 경유 직렬화와 sqlite event JSON 저장 경로에 `live_session_id`/`liveSessionId`를 추가했다.
- dev web server API 이벤트 JSON에도 `liveSessionId`를 노출하도록 맞췄다.
- `contents.dart`에서 live/bidi 히스토리일 때 현재 에이전트가 쓴 이벤트도 other-agent context처럼 취급하도록 조정했다.

작업 이유
- upstream이 live Gemini 응답에 `live_session_id`를 추가했고, live transfer/replay 문맥에서 history 해석 규칙도 함께 바뀌었다.
- Dart 쪽에 이 값이 없으면 live 세션 단위 추적과 history 재구성이 Python 대비 약해진다.
- 이벤트 저장과 API 노출까지 같이 맞춰야 실제 런타임, 세션 persistence, 디버그 도구가 동일한 값을 볼 수 있다.

## 작업 단위 3. `LoopAgent` pause 시 sub-agent state 보존

작업 내용
- `LoopAgent`가 pause 이벤트를 만난 경우 현재 iteration 종료 직후 `resetSubAgentStates()`를 호출하지 않도록 수정했다.
- pause 상태에서 하위 agent state가 유지되는 회귀 테스트를 추가했다.

작업 이유
- upstream은 pause 시 resumability state를 지우는 버그를 이미 수정했다.
- 기존 Dart 구현은 pause 후 resume에서 하위 agent state를 잃을 수 있었고, long-running tool resume 흐름에서 Python과 다르게 동작할 여지가 있었다.

## 작업 단위 4. Web server `user_id` / `session_id` path traversal 방어

작업 내용
- dev web server에 `user_id`, `session_id` 전용 검증 함수를 추가했다.
- Python-style route path segment, legacy API body/query, `/run`, `/run_live`, memory/session 생성 경로에 같은 검증을 적용했다.
- `.` / `..` / `/` / `\`가 포함된 식별자를 `400 Bad Request`로 거절하도록 맞췄다.
- path/body/query 입력 각각에 대한 회귀 테스트를 추가했다.

작업 이유
- upstream web server는 최근 `user_id` / `session_id`에 대한 path traversal 방어를 강화했다.
- Dart dev server도 session/artifact/memory 경로를 조합해서 쓰기 때문에 같은 종류의 입력 검증이 필요했다.
- 이 검증은 라우팅 초입에서 공통 적용하는 편이 기능 추가 시 누락 가능성이 낮다.

## 작업 단위 5. 회귀 테스트 보강

작업 내용
- `skill_toolset`, `Gemini` live response, `LoopAgent`, sqlite persistence, session migration, contents/live-session history, dev web server path validation을 각각 테스트로 고정했다.
- 새 테스트 파일:
  - `test/contents_live_session_parity_test.dart`
  - `test/live_session_event_parity_test.dart`

작업 이유
- 이번 배치 변경은 대부분 “모델 응답 -> 이벤트 -> 저장 -> API”처럼 여러 계층을 가로지른다.
- 단일 단위 테스트만 있으면 중간 계층 누락을 놓치기 쉬워서, 기능별로 서로 다른 계층의 회귀를 따로 고정했다.

## 이번 배치에서 직접 포팅하지 않은 항목

다음 upstream 변경은 신규 서브시스템 또는 외부 연동 범위가 커서 이번 parity 배치에서는 제외했다.

- Firestore memory/session integration
- Parameter Manager integration
- Agent Identity / GCP auth provider
- VMaaS sandbox client / sandbox computer
- sandbox computer use sample/infra
- Python 전용 browser bundle 갱신

이 항목들은 “미검토”가 아니라, 현재 `adk_dart`에 동등 계층이 없거나 별도 설계가 필요한 신규 기능으로 분류했다.

## 검증

- `dart pub get`
- `dart format` 대상 파일 적용
- `dart analyze lib test`
  - error/warning 없음
  - 기존 info-level lint만 잔존
- 통과 테스트
  - `dart test test/skill_toolset_parity_test.dart test/models_parity_batch2_test.dart test/workflow_agents_test.dart test/contents_live_session_parity_test.dart test/live_session_event_parity_test.dart test/session_migration_parity_test.dart`
  - `dart test test/session_persistence_services_test.dart --plain-name "persists liveSessionId in sqlite event payload"`
  - `dart test test/dev_web_server_test.dart --plain-name "rejects python-style session routes with path traversal ids"`
  - `dart test test/dev_web_server_test.dart --plain-name "rejects run payloads with path traversal session ids"`
  - `dart test test/dev_web_server_test.dart --plain-name "rejects run_live websocket ids with path traversal"`

메모
- `dart test`는 macOS native asset(`libsqlite3.dylib`) 재작성 단계에서 병렬 실행 시 충돌할 수 있어서 순차 실행으로 검증했다.
