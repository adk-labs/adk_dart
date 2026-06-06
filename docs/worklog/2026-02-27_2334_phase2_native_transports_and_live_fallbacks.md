# Phase2 Native Transports and Live Fallbacks (2026-02-27 23:34)

## 이번 배치 목표
이전 배치 이후 남은 런타임 공백을 줄이고, 메모리/분석 경로에서 provider-native transport를 추가했다.

## 1) Python 계약 확인
참조:
- `ref/adk-python/src/google/adk/memory/vertex_ai_memory_bank_service.py`
- `ref/adk-python/src/google/adk/memory/vertex_ai_rag_memory_service.py`
- `ref/adk-python/src/google/adk/plugins/bigquery_agent_analytics_plugin.py`

핵심 계약:
- Vertex memory bank는 in-memory만이 아니라 실제 provider 호출 경로가 필요
- BigQuery analytics는 sink 기반을 넘어 provider write 경로가 있어야 함
- Live 경로는 가능한 경우 async 경로 폴백으로 실제 동작해야 함

## 2) 구현 변경
### A. Vertex Memory Bank native HTTP client 추가
- 파일: `lib/src/memory/vertex_ai_memory_bank_service.dart`
- 추가:
  - `VertexAiMemoryBankHttpApiClient`
  - 기본 access token provider(환경변수 기반)
  - operation별 URI builder(`generate/create/retrieve`)
  - retrieve 응답 파싱 유틸
- 동작:
  - 프로젝트/리전 또는 API 키가 있으면 기본 factory가 HTTP client를 선택
  - 그렇지 않으면 기존 in-memory fallback 유지

### B. BigQuery analytics native sink 추가
- 파일: `lib/src/plugins/bigquery_agent_analytics_plugin.dart`
- 추가:
  - `BigQueryInsertAllEventSink` (`insertAll` REST 경로)
  - JSON-safe row 직렬화
  - access token/env provider
- 플러그인 확장:
  - `useBigQueryInsertAllSink`, `accessToken`, `apiKey`, `httpClient`, `accessTokenProvider` 옵션 추가
  - 기본은 기존 in-memory sink 유지 (호환성 보존)

### C. Live runtime 공백 제거
- 파일:
  - `lib/src/agents/loop_agent.dart`
  - `lib/src/agents/parallel_agent.dart`
- 변경:
  - `runLiveImpl`가 `UnsupportedError`를 던지지 않고 `runAsyncImpl`로 폴백

### D. Parity 상태 갱신
- 파일: `python_parity_status.md`
- 변경:
  - 남아있던 optional provider-native integration 항목을 구현 내용으로 완료 처리

## 3) 테스트 추가/수정
- `test/vertex_memory_services_parity_test.dart`
  - HTTP memory bank client 요청 shape/헤더/응답 파싱 검증
- `test/bigquery_agent_analytics_plugin_parity_test.dart`
  - native insertAll sink 배치/인증 헤더 검증
  - plugin의 native sink 사용 경로 검증
- `test/workflow_agents_test.dart`
  - Loop/Parallel runLive 기대값을 실제 fallback 동작 검증으로 변경

## 4) 검증 결과
- `dart format .` ✅
- `dart analyze` ✅ (errors 0 / warnings 0 / infos 69)
- `dart test` ✅ (656 passed, 1 skipped, 0 failed)

## 5) 학습 포인트
1. “기본은 안전한 fallback + 옵션으로 native transport” 구조가 포팅 단계에서 회귀를 줄인다.
2. provider-native sink/client는 외부 의존성을 강제하지 않도록 auth/provider를 주입 가능하게 두는 것이 유지보수에 유리하다.
3. `runLive` 미지원 예외는 실제 운영에서 즉시 장애가 되므로, 가능한 경우 async 경로 폴백이 우선이다.
