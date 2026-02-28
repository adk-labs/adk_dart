# ADK Dart 실동작 준비도 전수조사 (2026-02-28 11:29:46)

## 1) 조사 목적
1:1 포팅 완료 관점이 아니라, **실제 동작 가능성(런타임/외부 연동/엣지 케이스)** 기준으로 현재 상태를 전수 점검한다.

## 2) 조사 범위 및 방법
- 코드 범위: `lib/src/**` 전체 (`471` files)
- 테스트 범위: `test/**` 전체 (`121` files)
- 계약 기준:
  - `ref/adk-python/pyproject.toml`
  - `ref/adk-python/src/google/adk/**`
  - `python_parity_status.md`
- 실행 검증:
  - `dart analyze` (PASS, info 70)
  - `dart test` (PASS, `+674`, `~1 skipped`)

## 3) 정량 스냅샷

### 3.1 Python parity 체크리스트
- `python_parity_status.md` 체크 결과
  - 완료: `352`
  - 미완료: `0`

### 3.2 모듈 규모 (lib/src 상위 폴더)
- `tools` 125
- `cli` 87
- `evaluation` 53
- `agents` 27
- `flows` 19
- `auth` 18
- `sessions` 16
- `utils` 15
- `models` 15
- `a2a` 13
- (나머지 소규모 모듈 포함 총 471)

### 3.3 미구현성 시그널(코드 검색 기반)
`throw UnsupportedError | UnimplementedError` 검색 결과: `5`건
- [lib/src/agents/base_agent.dart:132](/Users/jaichang/Documents/GitHub/adk-dart/adk_dart/lib/src/agents/base_agent.dart:132)
  - `clone()` 기본 추상 동작 (의도된 subclass 구현 포인트)
- [lib/src/models/gemini_rest_api_client.dart:52](/Users/jaichang/Documents/GitHub/adk-dart/adk_dart/lib/src/models/gemini_rest_api_client.dart:52)
- [lib/src/models/gemini_rest_api_client.dart:65](/Users/jaichang/Documents/GitHub/adk-dart/adk_dart/lib/src/models/gemini_rest_api_client.dart:65)
  - `GeminiRestTransport` 기본 인터페이스에서 interactions 미지원 transport에 대한 명시적 예외 (의도된 extension point)
- [lib/src/sessions/database_session_service.dart:25](/Users/jaichang/Documents/GitHub/adk-dart/adk_dart/lib/src/sessions/database_session_service.dart:25)
  - sqlite/in-memory 외 DB URL 미지원 (현행 스코프 제한)
- [lib/src/tools/spanner/search_tool.dart:193](/Users/jaichang/Documents/GitHub/adk-dart/adk_dart/lib/src/tools/spanner/search_tool.dart:193)
  - PostgreSQL dialect에서 ANN 미지원 (기능 제한 명시)

해석: "TODO/placeholder 미해결"이라기보다, 대부분 **의도된 범위 제한/확장 포인트**다.

## 4) 실동작 준비도 평가

## 4.1 코어 런타임 준비도: **상 (약 90~95%)**
근거:
- agents/flows/models/sessions/evaluation/tooling 기본 경로가 테스트로 지속 검증됨
- `dart test` 전체 통과 (`674 pass`)
- 최근 배치에서 interactions/gemini-rest/sqlite/auth/plugin 예외경계 보강 완료

## 4.2 외부 연동 준비도: **중상 (약 75~85%)**
근거:
- 주요 연동군에 parity 테스트 존재:
  - BigQuery, Bigtable, Spanner, PubSub, OpenAPI, APIHub, Application Integration, MCP, Vertex memory, Auth/OAuth 등
- 다만 일부 연동은 "즉시 사용"보다 "주입/설정 후 사용" 구조
  - client factory / embedder 미주입 시 명시적 `NotConfigured` 예외
  - 실제 운영에서 infra wiring 필요

## 5) 외부 연동 관점 상세

### 5.1 이미 실동작 경계가 잘 정의된 영역
- Gemini REST/Interactions
  - 헤더 정규화, retry/backoff, malformed JSON/SSE 에러 표면화
- SQLite 세션
  - `sqlite://:memory:` 포함 URL 변형, read-only/memory 경계 테스트
- OAuth2/auth pipeline
  - `id_token` 보존, exchange 실패 시 초기 credential 상태 보존
- Plugin lifecycle
  - after-run callback 예외 문맥 래핑

### 5.2 운영 투입 전 추가 확인이 필요한 영역
- Spanner
  - ANN on PostgreSQL 미지원 (GoogleSQL path 중심)
  - embedder/client factory 주입 필수
- Bigtable/BigQuery/Discovery Engine 등 일부 Google 연동
  - SDK/REST adapter는 준비되어 있으나 환경 토큰·권한·엔드포인트 wiring 필요
- `DatabaseSessionService`
  - Python SQLAlchemy 수준의 다중 DB dialect 지원까지는 범위를 제한해 둔 상태

## 6) Python 의존성 대비 Dart 호환성 관점

`pyproject.toml` 기준 Python 핵심 의존성군은 Dart에서 다음 방식으로 대응 중:
- HTTP 계층(`httpx`/`requests`) -> Dart `http`
- OAuth/Google auth (`authlib`/`google-auth`) -> 현재 주입형 exchanger/refresher + credential flow
- GCP 데이터 서비스군(BigQuery/Bigtable/PubSub/Spanner/GCS/Vertex) -> 툴셋/클라이언트 abstraction + 테스트 스텁/주입형 런타임

평가:
- "API surface parity"는 높다.
- "실서비스 연동 parity"는 환경 의존 요소(토큰/권한/factory 주입)까지 자동화하면 한 단계 더 올라간다.

## 7) 리스크 요약 (우선순위)

### P1
- 다중 DB dialect(MySQL/PostgreSQL/Spanner SQLAlchemy parity) 미지원
- 일부 GCP integration의 런타임 wiring(credential/provider) 수동성

### P2
- Spanner PostgreSQL + ANN 경로 미지원
- Discovery/Bigtable/Spanner 계열에서 factory 미주입 시 즉시 실패 (설계상 정상이나 운영 문서/부트스트랩 강화 필요)

### P3
- info-level lint 70건 (품질엔 영향 낮으나 장기 유지보수 비용 증가)

## 8) 결론
현재 상태는 **코어 런타임 실동작은 높은 수준으로 안정화**되었고, **외부 연동은 “구조적으로는 준비됨 + 운영 wiring이 남은 상태”**다.

즉,
- 로컬/테스트 환경: 즉시 실동작 가능
- 운영/GCP 실연동: credential/provider/bootstrap 자동화 수준에 따라 체감 완성도 차이 발생

