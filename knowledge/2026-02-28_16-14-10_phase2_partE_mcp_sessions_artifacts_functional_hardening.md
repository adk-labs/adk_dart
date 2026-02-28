# Phase2 PartE Functional Hardening (MCP + Sessions + Artifacts)

작성 시각: 2026-02-28 16:14:10

## 1) Python 기준 동작 계약 확인
- 기준 소스
  - `ref/adk-python/src/google/adk/sessions/sqlite_session_service.py`
  - `ref/adk-python/pyproject.toml`
- 확인한 핵심 계약
  - SQLite 세션 서비스는 실제 SQLite 테이블(`app_states`, `user_states`, `sessions`, `events`) 기반으로 동작해야 한다.
  - 세션 조회는 이벤트 필터(`after_timestamp`, `num_recent_events`)를 지원해야 한다.
  - 상태 델타는 app/user/session prefix 규칙에 맞춰 merge/persist 해야 한다.
  - MCP는 도구/리소스/프롬프트를 원격 JSON-RPC 경로에서도 호출 가능해야 한다.
  - 아티팩트(GCS)는 mock/in-memory 경로와 live 연동 경로가 명확히 분리되고, live는 설정 누락 시 fail-fast 해야 한다.

## 2) Dart 구현 검수/수정

### A. MCP 원격 동작 강화
- 파일
  - `lib/src/tools/mcp_tool/mcp_session_manager.dart`
  - `lib/src/tools/mcp_tool/mcp_toolset.dart`
  - `lib/src/agents/mcp_instruction_provider.dart`
  - `test/mcp_http_integration_test.dart` (신규)
- 반영 내용
  - JSON-RPC 에러를 구조적으로 파싱/전파하도록 개선.
  - `initialize` 실패 캐시 정책을 보완해 일시 실패 시 재시도 가능.
  - 비HTTP URL은 기존 로컬 동작만 수행하도록 경계 유지.
  - 원격 `tools/list`, `tools/call`, `resources/list`, `resources/read`, `prompts/list/get` 흐름 검증.

### B. Session 실제 SQLite 백엔드 전환
- 파일
  - `lib/src/sessions/sqlite_session_service.dart`
  - `test/session_persistence_services_test.dart`
- 반영 내용
  - 기존 JSON 파일 저장 흉내 구현을 제거하고 실제 SQLite 엔진 기반 저장/조회로 교체.
  - create/get/list/delete/append 전 경로를 SQL 기반으로 구현.
  - stale session 보호, temp state trimming, state delta merge 계약 유지.
  - sqlite URL 파싱/absolute/relative/memory/read-only edge case 동작 유지.

### C. GCS Artifact live 경로 도입 + fail-fast
- 파일
  - `lib/src/artifacts/gcs_artifact_service.dart`
  - `test/apps_artifacts_parity_test.dart`
- 반영 내용
  - `GcsArtifactMode.inMemory` / `GcsArtifactMode.live` 모드 분리.
  - live 모드에서 HTTP request provider + auth headers provider 주입형 브릿지 도입.
  - live 모드 필수 주입 누락 시 즉시 예외(fail-fast).
  - in-memory는 테스트/로컬용 명시 모드로만 유지.
  - canonical gs:// URI 정규화 및 버전 메타데이터 조회 동작 검증.

## 3) 테스트 추가/수정
- 신규
  - `test/mcp_http_integration_test.dart`
- 수정
  - `test/session_persistence_services_test.dart`
  - `test/apps_artifacts_parity_test.dart`

## 4) 검증 실행 결과
- `dart format .` : PASS (555 files, 0 changed)
- `dart analyze` : PASS (info 70, warning/error 0)
- `dart test` : PASS (711 passed, 1 skipped, 0 failed)

## 5) 학습/공유 포인트
- "TODO 없음"은 실동작 보장과 다르다. fallback 기본값을 live 기본값으로 두면 운영 사고로 이어질 수 있어 명시적 모드 분리가 중요하다.
- 외부 연동 컴포넌트는 success path만큼 fail-fast 메시지 품질이 중요하다.
- MCP/Artifacts처럼 프로토콜 기반 모듈은 에러 전파 규칙을 테스트로 고정해야 회귀를 막을 수 있다.

## 6) 남은 구현 백로그(우선순위)
1. `VertexAiSessionService` 실제 원격 세션 백엔드 연동(현재 in-memory 위임)
2. `DatabaseSessionService` non-sqlite dialect 기본 어댑터(예: PostgreSQL) 또는 공식 bootstrap 제공
3. `code_executors` preflight 강화(환경/권한/의존성 누락 시 즉시 진단)
4. `memory`/`evaluation` live credentialed smoke lane CI 분리
5. `models` provider별 fallback 정책 명확화(테스트 대역 vs 운영 실패)
