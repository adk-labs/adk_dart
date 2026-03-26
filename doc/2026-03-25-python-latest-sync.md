# 2026-03-25 Python Latest Sync

검토 범위

- `ref/adk-python` `4cbc3dcb..2a90fbc1`

작업 단위

1. Discovery Engine regional endpoint parity
- 작업 내용
  - `DiscoveryEngineSearchTool`에 `location` 옵션을 추가했다.
  - `data_store_id` / `search_engine_id`에서 `locations/<region>`을 추론해 regional endpoint로 요청하도록 바꿨다.
  - `location` override, 빈 값, 잘못된 location 문자, resource/location 불일치에 대한 회귀 테스트를 추가했다.
- 작업 이유
  - Python upstream `30b904e5`는 regional Discovery Engine endpoint를 지원하도록 바뀌었다.
  - Dart는 항상 global endpoint만 사용하고 있어서 `eu`, `us`, `europe-west1` 같은 regional resource에서 parity gap이 있었다.

2. Dev web server same-origin protection parity
- 작업 내용
  - dev web server에 same-origin 검사를 추가해서 `POST`, `PATCH`, `DELETE` 같은 state-changing 요청은 기본적으로 same-origin만 허용하도록 바꿨다.
  - `allowOrigins`가 명시된 경우에는 그 allow list를 계속 우선 적용한다.
  - `run_live` WebSocket도 `Origin` 헤더를 검사해서 허용되지 않은 origin이면 `1008 policy violation`으로 닫도록 했다.
  - 기본값에서 wildcard CORS 헤더를 더 이상 자동으로 내보내지 않도록 조정하고 회귀 테스트를 추가했다.
- 작업 이유
  - Python upstream `995cd1cb`는 browser-origin 기반의 cross-origin state-changing 요청을 막는 보호 로직을 추가했다.
  - Dart는 CORS 헤더만 처리하고 실제 요청 차단은 없어서 CSRF 성격의 parity gap이 있었다.

3. Session events index parity
- 작업 내용
  - SQLite session store 준비 단계에서 `idx_events_app_user_session_ts` 인덱스를 항상 생성하도록 추가했다.
  - 기존 DB에서 인덱스가 삭제된 경우 서비스 재오픈 시 다시 만들어지는 회귀 테스트를 추가했다.
  - network DB schema도 같은 인덱스 이름과 정렬 기준(`timestamp DESC`)으로 맞췄다.
- 작업 이유
  - Python upstream `3153e6d7`는 events 조회 성능을 위해 최신 schema에 `events(app_name, user_id, session_id, timestamp desc)` 인덱스를 추가했다.
  - Dart SQLite 구현은 대응 인덱스가 없어서 최근 이벤트 조회 경로와 parity가 맞지 않았다.

4. Function declaration required-field review
- 작업 내용
  - explicit JSON schema 경로에서 nested `required`가 유지되는 회귀 테스트를 추가했다.
- 작업 이유
  - Python upstream `c5d809e1`는 Pydantic `BaseModel` 파라미터의 `required` 필드를 보강했다.
  - Dart는 Pydantic 타입 계층이 없고 explicit JSON schema를 직접 넘기는 구조라서 동일 패치는 필요 없었지만, 개념적으로 대응되는 `required` 보존 동작은 테스트로 고정했다.

직접 포팅하지 않은 항목

- `scripts/unittests.sh` 개선: Dart 저장소 구조와 테스트 진입점이 달라 직접 대응 대상이 아니다.
- Python release/dependency bump: Dart 런타임/패키지 의존성 체계와 직접 연결되지 않는다.
- FastAPI builder-specific 경로 변경: Dart dev server는 동일한 builder surface를 제공하지 않아서 same-origin 보호를 공통 HTTP/WebSocket 계층에 적용했다.

검증 계획

- `dart format` on changed files
- `dart analyze` on touched sources
- `dart test`:
  - `test/tools_search_grounding_parity_test.dart`
  - `test/tools_schema_utils_test.dart`
  - `test/dev_web_server_test.dart`
  - `test/session_persistence_services_test.dart`
