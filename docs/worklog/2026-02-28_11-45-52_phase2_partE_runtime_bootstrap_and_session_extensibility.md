# Phase2 Part E - Runtime Bootstrap & Session Extensibility

- Date: 2026-02-28 11:45:52
- Scope: `lib/src/sessions`, `lib/src/tools/spanner`, `lib/src/tools/pubsub`, `test`

## 1) Python 기준 동작 계약 확인

참조:
- `ref/adk-python/src/google/adk/sessions/database_session_service.py`
- `ref/adk-python/pyproject.toml`
- Spanner/PubSub 관련 Python 패턴(외부 client 주입형 구조)

핵심 포인트:
- DB 세션 서비스는 URL 기반으로 백엔드를 선택해야 하며, 스코프 밖 URL은 확장 가능한 경로가 필요
- 외부 연동(Spanner/PubSub)은 런타임 주입(wiring) 없이 실사용이 어렵기 때문에 bootstrap 진입점이 필요

## 2) Dart 구현 검수 및 수정

### A. DatabaseSessionService 확장 가능화
- 파일: `lib/src/sessions/database_session_service.dart`
- 추가:
  - `registerCustomFactory` / `unregisterCustomFactory`
  - `registerCustomResolver` / `unregisterCustomResolver`
  - `resetCustomResolversAndFactories`
- 동작:
  - 기존 sqlite/in-memory dispatch는 우선 유지
  - 비기본 scheme은 custom factory/resolver로 연결 가능

### B. Spanner/PubSub 통합 bootstrap helper
- 파일: `lib/src/tools/spanner/utils.dart`
- 추가:
  - `configureSpannerPubSubRuntime(...)`
  - `resetSpannerPubSubRuntime(...)`
- 동작:
  - Spanner client/embedder, PubSub publisher/subscriber factory를 한 번에 구성
  - reset 시 PubSub 캐시 클라이언트 정리 옵션 제공

## 3) 테스트 추가/수정

- 수정: `test/session_persistence_services_test.dart`
  - custom factory/resolver 등록 경로 검증
  - sqlite 우선순위(기본 dispatch precedence) 회귀 방지 검증
- 추가: `test/spanner_pubsub_runtime_bootstrap_test.dart`
  - 통합 bootstrap configure/reset 동작 검증
  - reset 시 cleanup 옵션 동작 검증

## 4) 검증 결과

- `dart format .` ✅
- `dart analyze` ✅ (errors 0 / warnings 0 / info 70)
- `dart test` ✅ (`679 passed`, `1 skipped`, `0 failed`)

## 5) 학습/운영 포인트

1. 외부 연동 readiness는 기능 구현 자체보다 "초기 wiring 진입점" 유무가 체감 완성도를 좌우한다.
2. DB URL 확장은 기본 경로를 건드리지 않고 registry 방식으로 여는 것이 회귀 리스크가 낮다.
3. 테스트에서는 global static registry를 reset해서 격리성을 보장해야 flaky를 줄일 수 있다.

## 6) 남은 리스크

- custom registry가 static state라 장기적으로는 scoped registry(예: runtime context별) 도입 여지 있음
- sqlite/in-memory 외 실제 production DB adapter 구현은 다음 배치(Part F/G)에서 진행 필요
