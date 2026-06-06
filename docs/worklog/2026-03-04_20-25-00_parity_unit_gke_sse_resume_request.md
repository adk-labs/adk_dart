# Parity Unit: GKE Execute-Type + SSE Resume Handling (Python 2026-03-03 반영)

- Date: 2026-03-04
- Scope:
  - `lib/src/code_executors/code_execution_utils.dart`
  - `lib/src/code_executors/gke_code_executor.dart`
  - `lib/src/dev/web_server.dart`
  - `test/code_execution_parity_test.dart`
  - `test/dev_web_server_test.dart`
- Reference upstream changes:
  - `9c451662` (GkeCodeExecutor execute-type 파라미터)
  - `6a929af7` (run_sse artifactDelta split 예외: function resume request)

## 구현 내용

1. GKE executeType 파라미터 반영
- `CodeExecutionInput`에 `executeType` 필드 추가.
- `GkeCodeExecutor.createJobManifest(...)`에 `executeType` 인자 추가.
- Job metadata annotation에 `adk.agent.google.com/execute-type` 기록.
- `executeCode` 경로에서 `codeExecutionInput.executeType` 전달.

2. run_sse function-resume 분기 추가
- `isFunctionResumeRequest(...)` helper 추가:
  - `invocationId`가 있고,
  - `newMessage`에 `function_response` part가 있으면 resume request로 판정.
- `buildSseEventsForRun(...)` helper 추가:
  - 일반 요청은 기존대로 artifactDelta/content split.
  - resume request는 split하지 않고 원본 이벤트 단일 전송.

## 검증

- Added tests:
  - `code_execution_parity_test.dart`
    - gke manifest execute-type annotation
    - executeCode 경로에서 execute-type 전파
  - `dev_web_server_test.dart`
    - 일반 요청 split 유지
    - resume 요청 split 방지

- Executed:
  - `dart analyze` (changed files)
  - `dart test test/a2a_parity_test.dart test/tools_parity_test.dart test/code_execution_parity_test.dart test/dev_web_server_test.dart`

## 결과

- GKE 실행 타입 힌트 전달 경로 추가.
- long-running function resume 시 SSE 이벤트 분할로 인한 동작 왜곡 가능성을 방지.

