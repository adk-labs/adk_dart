# ADK Web Parity Status (Dart vs ref/adk-python)

기준일: 2026-02-28

## 사실 검증
- `ref/adk-python`의 `adk web`은 별도 외부 웹 프로세스를 띄우는 방식이 아님.
- FastAPI 앱이 패키지 내부의 `cli/browser` 정적 자산을 `/dev-ui`로 마운트해 서빙함.

## 이번 반영 완료
- `adk web`/`adk api_server` CLI 파라미터 확장
  - `--allow_origins`
  - `--url_prefix`
  - `--session_service_uri`
  - `--artifact_service_uri`
  - `--memory_service_uri`
  - `--use_local_storage` / `--no-use_local_storage`
  - `--auto_create_session`
  - `--logo_text`
  - `--logo_image_url`
  - python 호환용 일부 옵션 파싱 수용: `--trace_to_cloud`, `--otel_to_cloud`, `--reload`, `--a2a`, `--reload_agents`, `--extra_plugins`
- `api_server` 모드 분리
  - CLI에서 `api_server`는 `enableWebUi=false`로 실행
- 내장 UI 서빙 방식 정렬
  - 패키지 `src/cli/browser`를 `/dev-ui/`로 서빙
  - `/` -> `/dev-ui/` 리다이렉트
  - `/dev-ui/config` 제공
- API 표면 확장
  - `GET /health`
  - `GET /version`
  - `GET /list-apps` (`?detailed=true` 포함)
  - `POST /run`
  - `POST /run_sse`
  - `GET /run_live` (WebSocket)
  - python 스타일 세션 경로
    - `GET/POST /apps/{app}/users/{user}/sessions`
    - `GET/POST/PATCH/DELETE /apps/{app}/users/{user}/sessions/{session}`
  - 메모리 경로
    - `PATCH /apps/{app}/users/{user}/memory`
  - 아티팩트 경로
    - `GET/POST /apps/{app}/users/{user}/sessions/{session}/artifacts`
    - `GET/DELETE /apps/{app}/users/{user}/sessions/{session}/artifacts/{name}`
    - `GET /.../artifacts/{name}/versions`
    - `GET /.../artifacts/{name}/versions/metadata`
    - `GET /.../artifacts/{name}/versions/{version}`
    - `GET /.../artifacts/{name}/versions/{version}/metadata`
- 레거시 호환 유지
  - 기존 `/api/sessions`, `/api/sessions/{id}/messages`, `/api/sessions/{id}/events` 유지

## 검증
- `dart test test/dev_cli_test.dart test/dev_web_server_test.dart test/cli_adk_web_server_test.dart` 통과
- `dart analyze` (관련 파일) 통과

## 남은 주요 갭 (Python 대비)
- 평가(Eval) 엔드포인트 전반 (`/apps/{app}/eval-*`, `/metrics-info` 등)
- 디버그/트레이스 상세 엔드포인트 (`/debug/trace/*`, `/dev/build_graph/*`)
- `run_sse`의 세부 이벤트 분해/호환성 (artifactDelta 분리 스트리밍 등 세밀한 동작)
- `run_live`의 Python 수준 옵션/오류코드 세밀 호환 (`modalities` 외 세부 쿼리/proactivity/session resumption)
- `trace_to_cloud` / `otel_to_cloud` / `reload_agents` / `a2a` / `extra_plugins` 실구현
- CORS 정규식/헤더 동작의 Python 미들웨어 레벨 완전 동일화

## 다음 구현 우선순위 제안
1. Eval API 묶음 구현
2. Debug/Trace API 구현
3. Streaming 세부 동작(run_sse/run_live) 이벤트 포맷 완전 정렬
4. 옵션 실구현(trace/otel/reload_agents/a2a/plugins)
