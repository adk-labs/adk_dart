# Phase2 4-Folder Batch Functional Hardening (2026-02-28 15:24)

## 목적
- 1:1 포팅 상태에서 실제 동작 단계로 전환하기 위해, 4폴더 단위 병렬 작업으로 실동작/외부연동/엣지케이스 리스크를 제거했다.

## 작업 분할 (에이전트 병렬)
- Part A: `sessions`, `artifacts`, `tools`, `code_executors`
- Part B: `models`, `agents`, `flows`, `memory`
- Part C: `evaluation`, `plugins`, `platform`, `cli`

## Python 계약 확인 포인트
- `InMemorySessionService.append_event`는 Python 기준 세션 미존재 시 예외 대신 경고 후 이벤트 반환(fail-open) 동작이다.
- Dart도 해당 계약으로 정렬(예외 throw 제거)했다.
- `AgentEvaluator`는 modern eval set(Map) 입력 파싱 실패를 레거시(List)로 무조건 폴백하면 안 되고, Map 파싱 실패는 명시 실패가 맞다.

## 구현/수정 요약
1. Live/Flow 안정성
- live 종료 경로의 `connection.close()` 중복 호출 제거.
- live partial function-call chunk는 도구 실행하지 않도록 가드 추가.
- `LiveRequestQueue` 종료 상태(`_closed`) 도입: close idempotent + close 이후 send 무시.

2. Session/Storage 정확성
- SQLite URL 절대경로(`sqlite:///...`, `sqlite+aiosqlite:///...`) 파싱 보정.
- in-memory append_event를 Python 계약에 맞춰 세션 미존재 시 이벤트 반환으로 정렬.

3. 보안/경계 강화
- `FileArtifactService` metadata `canonicalUri` fallback 시 rootDir 밖 경로 차단.
- `GcsStorageStore`에서 `blobName` path traversal(`..`, 절대경로) 차단 + canonical prefix 검증.

4. 평가/캐시 동작 보정
- `AgentEvaluator` modern(Map) 파싱 실패 시 명시 예외 전파, legacy(List)만 폴백 허용.
- `RequestIntercepterPlugin` 캐시 evict + 상한(`maxCachedRequests`) 도입.

5. 외부 웹 연동 안전성
- `load_web_page`에 timeout/최대 응답 바이트 제한 추가, 네트워크/HTTP 실패 메시지 명확화.

6. Memory 계약 보강
- `InMemoryMemoryService.addEventsToMemory`에서 `customMetadata` 병합 저장.

## 테스트 추가/수정
- 신규
  - `test/gcs_storage_store_test.dart`
  - `test/load_web_page_test.dart`
- 주요 수정
  - `test/agent_evaluator_parity_test.dart`
  - `test/request_intercepter_plugin_test.dart`
  - `test/apps_artifacts_parity_test.dart`
  - `test/live_flow_fallback_test.dart`
  - `test/live_request_queue_test.dart`
  - `test/llm_flow_live_modules_parity_test.dart`
  - `test/memory_service_test.dart`
  - `test/session_persistence_services_test.dart`

## 검증 실행 결과
- `dart format .`: 성공
- `dart analyze`: 성공 (info 70)
- `dart test`: 성공 (전체 통과, skip 1)

## adk-python 의존성 대비 Dart 패키지 호환 조사 (이번 배치에서 확인)
- DB/세션
  - SQLite: `sqlite3`, `sqflite_common`
  - PostgreSQL: `postgres`
- Google API/Auth
  - OAuth/ADC: `googleapis_auth`
  - Google API client set: `googleapis` (BigQuery/Storage/Spanner API 포함)
- Telemetry
  - OpenTelemetry: `opentelemetry`
- 참고
  - 고수준 GCP 헬퍼: `gcloud` (Storage/PubSub 포함, 성숙도/유지보수성 별도 검토 필요)

## 학습/다음 단계
- 포팅 완료 여부보다 중요한 것은 실패 모드의 일관성(fail-open/fail-closed)과 경계 검증(path/canonical)이다.
- 다음 배치 우선순위:
  1. `code_executors` 입력 파일 경로 sanitize 공통화
  2. `plugins` 관측성 강화(예외 삼킴 최소화)
  3. `tools` 외부 호출 preflight/fail-fast 강화
