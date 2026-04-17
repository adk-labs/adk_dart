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

## 작업 단위 6. live session resumption / `goAway` / reconnect parity

작업 내용
- `LlmResponse`, `Event`에 `liveSessionResumptionUpdate`, `goAway` 필드를 추가했다.
- `GeminiLlmConnection` live receive 경로가 resumption update와 `goAway`를 제어 응답으로 그대로 내보내도록 수정했다.
- `BaseLlmFlow.runLive()`에 재연결 루프를 추가해서 recoverable live disconnect와 `goAway` 이후 재접속을 처리하도록 맞췄다.
- live session resumption handle이 이미 있으면 reconnect 시 history를 다시 보내지 않도록 조정했다.
- resumption update만 있는 응답도 control event로 surface해서 상위 호출자가 관찰하고 저장할 수 있게 했다.

작업 이유
- upstream Python은 live reconnect, resumption handle 갱신, `go_away` 제어 메시지 처리를 이미 런타임 의미로 사용하고 있다.
- 기존 Dart 구현은 handle을 메모리에만 갱신하거나 live 종료로 흘려보내서, reconnect 전략과 세션 복구 가시성이 Python보다 약했다.
- 이 레이어를 맞춰야 live transfer, reconnect, session persistence가 같은 의미를 가진다.

## 작업 단위 7. live input transcription author parity

작업 내용
- `BaseLlmFlow`가 `inputTranscription` 응답을 사용자 발화로 분류하도록 author 결정 규칙을 수정했다.
- live handoff/history 재구성 테스트에 input transcription author 회귀 케이스를 추가했다.

작업 이유
- upstream은 live input transcription을 `user` authored event로 다루도록 수정했다.
- 기존 Dart 구현은 `content.role == user`인 경우에만 사용자 이벤트로 취급해서, content 없는 transcription 제어 응답을 현재 agent authored event로 잘못 저장할 수 있었다.
- 이 차이는 transfer/current-turn history 계산에서 직접 드러나는 동작 차이라 parity 대상으로 봐야 한다.

## 작업 단위 8. plugin `onEventCallback` 저장 순서 parity

작업 내용
- `Runner`에서 plugin `onEventCallback`을 session append 이전에 실행하도록 순서를 조정했다.
- plugin이 수정한 event를 yield와 persistence가 동일하게 사용하도록 output event 조립 경로를 분리했다.
- run-level custom metadata 재적용이 plugin 수정 이벤트에도 유지되도록 보정했다.

작업 이유
- upstream은 plugin callback 결과가 스트림에만 보이고 세션에는 빠지는 문제를 이미 수정했다.
- 기존 Dart 구현은 callback 이후 yield되는 event와 append된 event가 달라질 수 있어서, 재로드 후 상태와 실시간 관찰 결과가 불일치했다.
- plugin 기반 analytics/metadata 확장에서는 저장본과 전송본이 같아야 후속 분석과 replay가 안정적이다.

## 작업 단위 9. live control field 저장/API 전파 보강

작업 내용
- schema v0, sqlite event JSON, dev web server event JSON에 `liveSessionResumptionUpdate`, `goAway`를 추가했다.
- session migration / sqlite persistence 테스트에 live control field roundtrip 검증을 넣었다.

작업 이유
- live control 필드를 모델 응답에서만 들고 있으면 reconnect 디버깅, 세션 재생, API 관찰 시점에 정보가 끊긴다.
- upstream parity는 “응답 수신 -> 이벤트 생성 -> 저장 -> API 노출” 전체 경로가 연결되어야 의미가 있다.
- 저장 계층과 API 계층을 같이 맞춰야 이전에 수정한 runtime parity가 실제 운영 경로에서도 유지된다.

## 작업 단위 10. `goAway` surface 및 clean EOF reconnect guard

작업 내용
- live flow가 `goAway` 응답을 reconnect 전에 control event로 먼저 yield하도록 수정했다.
- resumption handle이 있어도 receive stream이 정상 종료된 경우에는 자동 reconnect하지 않도록 정리했다.
- live flow 테스트에 `goAway` event surface 검증과 clean EOF non-reconnect 회귀 케이스를 추가했다.

작업 이유
- 기존 보완만으로는 `goAway` 필드가 타입과 저장 계층에는 존재해도 실제 live runtime에서는 throw가 먼저 일어나 이벤트가 surface되지 않았다.
- 또한 정상 EOF와 recoverable disconnect를 구분하지 않으면 resumption handle이 있는 세션에서 불필요한 재접속 루프가 발생할 수 있다.
- 이 두 건은 테스트 통과 여부보다 실제 live session 의미론에 직접 영향을 주는 런타임 버그라서 같은 sync 배치에서 닫는 편이 맞다.

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
  - `dart test test/llm_flow_live_modules_parity_test.dart`
  - `dart test test/models_parity_batch2_test.dart`
  - `dart test test/runner_flow_test.dart`
  - `dart test test/session_migration_parity_test.dart`
  - `dart test test/session_persistence_services_test.dart`
  - `dart test test/llm_flow_live_modules_parity_test.dart` (`goAway` surface / clean EOF non-reconnect 회귀 포함)
  - `dart test test/dev_web_server_test.dart --plain-name "rejects python-style session routes with path traversal ids"`
  - `dart test test/dev_web_server_test.dart --plain-name "rejects run payloads with path traversal session ids"`
  - `dart test test/dev_web_server_test.dart --plain-name "rejects run_live websocket ids with path traversal"`

메모
- `dart test`는 macOS native asset(`libsqlite3.dylib`) 재작성 단계에서 병렬 실행 시 충돌할 수 있어서 순차 실행으로 검증했다.
