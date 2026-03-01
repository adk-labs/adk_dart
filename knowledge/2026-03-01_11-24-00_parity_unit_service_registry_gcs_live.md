# Parity Unit: Service Registry `gs://` Live Wiring

작성 시각: 2026-03-01 11:24:00

## 배경
- `runtime_remaining_work_checklist.md` P0 항목 중 `gs://` 아티팩트 서비스가 런타임에서 즉시 실패하는 문제를 우선 처리.
- 원인: `ServiceRegistry`가 `GcsArtifactService`를 live provider 없이 생성.

## 반영 내용
- 파일: `lib/src/cli/service_registry.dart`
  - `gs://` 스킴 등록 시 아래 provider를 주입하도록 변경.
    - HTTP 전송 provider: `HttpClient` 기반 요청/응답 브릿지.
    - 인증 헤더 provider: `resolveDefaultGoogleAccessToken` 기반 Bearer 토큰 발급.
  - 버킷명 파서 추가:
    - `gs://bucket` 형태의 authority 우선.
    - authority가 비어있을 때 path segment fallback.
    - 둘 다 없으면 명시적 에러.
- 파일: `test/cli_service_registry_test.dart`
  - `gs://demo-bucket` URI가 `GcsArtifactService`로 해석되는 테스트 추가.

## 검증
- `dart analyze lib/src/cli/service_registry.dart test/cli_service_registry_test.dart` : PASS
- `dart test test/cli_service_registry_test.dart` : PASS

## 결과
- `gs://` artifact URI가 fail-fast 생성 오류 없이 live 경로로 초기화됨.
- 실제 인증 토큰 해석은 런타임 환경(환경변수/gcloud/metadata) 기준으로 동작.
