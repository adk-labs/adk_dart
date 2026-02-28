# Runtime Readiness P1/P2 실행 로드맵

- 기준 문서: `knowledge/2026-02-28_11-29-46_runtime_readiness_full_audit.md`
- 목표: "포팅 완료"를 넘어 운영 환경에서의 실동작 안정성 확보

## 1) 우선순위 정의

### P1 (즉시 착수)
- 다중 DB dialect 지원 전략 확정 및 최소 구현
- 외부 연동 bootstrap 자동화(credential/provider/factory 주입)
- 운영 기준 실패 가이드(에러 메시지 + 복구 절차) 표준화

### P2 (P1 완료 직후)
- Spanner PostgreSQL + ANN 대안 경로 지원
- GCP 연동군의 실환경 스모크 테스트 자동화
- lint/info debt 정리로 유지보수 비용 절감

## 2) 실행 계획

## Phase 1: DB 서비스 확장 (P1)
- 범위:
  - `DatabaseSessionService`에 sqlite 외 dialect 확장 가능 구조 도입
  - 최소 1개 추가 dialect(예: PostgreSQL)에 대한 adapter/facade 구현
- 산출물:
  - 설계 문서 1개 (dialect matrix, feature gap, migration policy)
  - 구현 + 회귀 테스트
- 완료 기준(DoD):
  - URL 파싱/검증/연결/CRUD 계약 테스트 통과
  - 기존 sqlite/in-memory 회귀 0

## Phase 2: 외부 연동 bootstrap 표준화 (P1)
- 범위:
  - BigQuery/Bigtable/Spanner/PubSub/Discovery/MemoryBank 경로의 factory/credential 자동 주입 진입점 통일
  - `NotConfigured` 예외 시 즉시 실행 가능한 remediation 메시지 제공
- 산출물:
  - `tooling bootstrap` helper (env -> provider/factory wiring)
  - 런북 문서(필수 env, 권한, 토큰 흐름)
- 완료 기준(DoD):
  - 로컬에서 샘플 env만으로 스모크 테스트 실행 가능
  - "설정 누락" 오류 시 해결 안내 문구가 1-step actionable

## Phase 3: 운영 스모크 테스트 파이프라인 (P2)
- 범위:
  - 통합 스모크 테스트 세트 추가
  - CI에서 선택적(비밀값 존재 시) 실연동 검증 잡 구성
- 대상 우선순위:
  - Auth/OAuth2
  - Gemini REST/Interactions
  - Session persistence
  - BigQuery/PubSub/Spanner 핵심 툴 경로
- 완료 기준(DoD):
  - 최소 1개 CI 잡에서 실연동 스모크 통과
  - 비밀값 미제공 환경에서도 graceful skip + 명확한 로그

## Phase 4: Spanner PG ANN 대안 및 품질 정리 (P2)
- 범위:
  - PG dialect에서 ANN 미지원 시 대체 경로(KNN/fallback) 표준화
  - info-level lint 상위 항목 우선 정리
- 완료 기준(DoD):
  - Spanner PG 경로에서 기능 제한이 있어도 사용자 시나리오 실패율 감소
  - analyze info 감소 추세(목표: 70 -> 40 이하 1차)

## 3) 작업 분할 제안 (4-folder 단위)

- Part E: `lib/src/sessions`, `lib/src/tools/spanner`, `lib/src/tools/pubsub`, `test`
- Part F: `lib/src/tools/bigquery`, `lib/src/tools/bigtable`, `lib/src/tools/discovery*`, `test`
- Part G: `lib/src/auth`, `lib/src/tools/openapi_tool`, `lib/src/plugins`, `test`
- Part H: `lib/src/memory`, `lib/src/models`, `lib/src/utils`, `test`

각 Part 공통 절차:
1. Python 계약 확인
2. Dart 구현/수정
3. 테스트 추가/수정
4. `dart format .`, `dart analyze`, `dart test`
5. knowledge 브리핑 문서
6. 커밋/푸시
7. 결과 리포트

## 4) 위험요소 및 대응

- 위험: 실연동 자격증명 미비로 테스트가 flaky
- 대응: fake/recorded fixture + optional live test 분리

- 위험: dialect 확장 시 기존 sqlite 회귀
- 대응: sqlite 회귀 테스트를 gate로 상시 유지

- 위험: factory 주입 구조 확장으로 초기화 경로 복잡화
- 대응: 단일 bootstrap 계층으로 진입점 통합

## 5) 권장 실행 순서
1. Phase 1 (DB 확장 설계+최소 구현)
2. Phase 2 (bootstrap 표준화)
3. Phase 3 (실연동 스모크 자동화)
4. Phase 4 (Spanner PG 대안 + lint 정리)

## 6) 즉시 착수 체크리스트
- [ ] Part E 에이전트 스폰 및 소유범위 확정
- [ ] DB dialect 설계 초안 작성
- [ ] bootstrap helper 초안 작성
- [ ] 스모크 테스트 템플릿(비밀값 유무 분기) 추가
