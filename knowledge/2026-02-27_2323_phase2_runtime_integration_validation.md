# Phase2 Runtime Integration Validation (2026-02-27 23:23)

## 목적
1:1 포팅 중심에서 벗어나 실제 동작 관점(실동작/외부 연동 경계/엣지 케이스)으로 런타임 안정성을 강화했다.

## 작업 범위 요약
- `lib/src/models`: Gemini REST transport 스트리밍/SSE 경계 케이스 하드닝
- `lib/src/sessions`, `lib/src/cli`: sqlite URL 계약 정합성 강화
- `lib/src/artifacts`, `lib/src/tools`: artifact fileData 및 로딩 안전 처리 강화
- 관련 테스트 보강

## Python 기준 동작 계약 확인
참조: `ref/adk-python`
- models: tracking headers 병합 시 필수 헤더 보존 계약
- sessions: sqlite URL 정규화(`sqlite:///relative`, `sqlite:////absolute`, `sqlite+aiosqlite`) 및 read-only mode 계약
- artifacts/tools: GCS artifact 버전/URI 메타데이터, artifact 로딩 시 모델 친화적인 표현 계약

## 구현 변경 상세
### 1) Gemini REST transport 하드닝
- 예약 헤더(`content-type`, `x-goog-api-key`)를 커스텀 헤더가 덮어쓰지 못하도록 보호(대소문자 무시)
- stream 요청에 `accept: text/event-stream` 기본값 주입
- SSE 파서 강화:
  - BOM/코멘트(`:`)/일반 SSE 필드(`event`, `data`, `id`, `retry`) 처리
  - 200 응답이지만 SSE 형식이 아닌 경우 명확한 예외 반환
- 스트리밍 에러 바디 UTF-8 손상 시에도 재시도 경로가 동작하도록 `allowMalformed` 디코딩 적용

### 2) Session sqlite URL 정합성 강화
- sqlite URL 파싱/검증을 `SqliteSessionService`로 일원화
- 공백 URL trim 처리 및 `DatabaseSessionService` dispatch 안정화
- 잘못된 URL에 대한 빠른 실패:
  - 빈 path, fragment, 미지원 query key
  - 미지원 `mode`
- `mode=ro` 지원: read-only 경로에서 쓰기 시 `FileSystemException`으로 명확히 실패
- CLI registry에서 sqlite 서비스 생성 시 원본 URI를 그대로 전달

### 3) Artifact 및 LoadArtifactsTool 하드닝
- `GcsArtifactService`에서 `fileData` artifact 저장/로드 지원
- 빈 `file_data.file_uri` 검증 추가
- `ArtifactVersion.canonicalUri`가 `fileData` URI를 보존하도록 개선
- inline MIME 빈값 정규화(`application/octet-stream` fallback)
- `LoadArtifactsTool` 안전 로딩 강화:
  - 지원되는 inline MIME은 그대로 유지
  - text-like MIME은 텍스트로 변환
  - binary inline은 설명 텍스트로 안전 요약
  - `fileData`는 placeholder 텍스트 대신 `fileData` 그대로 전달
  - `artifact_names`의 빈값/`null` 문자열 필터링

## 테스트 변경
- `test/gemini_rest_api_client_test.dart`
  - 헤더 충돌 시 필수 헤더 보존
  - malformed UTF-8 error body 재시도
  - 첫 chunk 송출 후 실패 시 재시도 금지
  - non-SSE 200 응답 실패 검증
- `test/session_persistence_services_test.dart`
  - sqlite URL relative/absolute 경로 폼
  - read-only mode 동작
  - 미지원 query/path 검증
  - URL trim dispatch
- `test/apps_artifacts_parity_test.dart`
  - fileData artifact 저장/로드 및 canonical URI 보존
  - 빈 file URI 검증
- `test/tools_memory_artifacts_test.dart`
  - unsupported inline MIME 안전 텍스트 변환
  - supported inline + fileData 보존

## 실행 결과
- `dart format .` ✅
- `dart analyze` ✅ (error 0, warning 0, info/lint 69)
- `dart test` ✅ (passed 653, failed 0, skipped 1)

## 의존성 관점 메모 (Python 대비 Dart)
Python 의존성 중 데이터베이스/스토리지/HTTP 관련 계약을 Dart에서 우선 런타임 행위로 맞췄다.
- `httpx`/`requests` 계열 계약: Dart `http`
- `aiosqlite` URL 계약: Dart session sqlite URL parser/validator
- `google-cloud-storage` artifact 계약: Dart GCS artifact naming + metadata/file URI 처리

현재 단계에서는 새 패키지 추가 없이, 기존 의존성으로 실제 동작 경계와 예외 계약을 먼저 강화했다.

## 배운 점 / 다음 학습 포인트
1. 포팅 완료 상태에서도 "실제 호출 경계"(헤더/스트림/URL/query 파라미터)에서 회귀가 가장 자주 발생한다.
2. SSE는 성공(200) 응답이라도 payload 형식이 잘못되면 즉시 식별 가능한 에러가 필요하다.
3. sqlite URL은 dialect/path/query 해석 차이가 커서, 파싱 로직을 단일 진입점으로 관리해야 유지보수가 쉽다.
4. artifact 로딩은 모델 입력 안전성(바이너리 처리)과 원본 참조 보존(file URI) 사이 균형이 중요하다.
