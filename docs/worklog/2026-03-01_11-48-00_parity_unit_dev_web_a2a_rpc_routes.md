# Parity Unit: Dev Web `--a2a` RPC Routes

작성 시각: 2026-03-01 11:48:00

## 배경
- `--a2a` 활성화 시 기존 구현은 agent card endpoint만 제공하고, 실제 A2A RPC 호출(`message/send`, `tasks/get` 등)은 동작하지 않음.

## 반영 내용
- 파일: `lib/src/dev/web_server.dart`
  - A2A RPC 라우트 파서 추가:
    - `POST /a2a/<app>`
    - `POST /a2a/<app>/v1/message:send`
    - `POST /a2a/<app>/v1/message:stream`
    - `POST /a2a/<app>/v1/tasks:get`
    - `POST /a2a/<app>/v1/tasks:cancel`
  - JSON-RPC 핸들러 추가:
    - `message/send`: `A2aAgentExecutor`를 통해 실제 러너 실행 후 message 결과 반환.
    - `message/stream`: 현재 실행 결과를 task 형태로 반환.
    - `tasks/get`: 서버 내 task store에서 task 조회.
    - `tasks/cancel`: task 상태를 failed/cancel 요청 상태로 갱신.
    - 미지원 method는 JSON-RPC 에러(`-32601`) 반환.
  - A2A 직렬화/역직렬화 유틸 추가:
    - message/part/task/status JSON 변환.
  - 서버 컨텍스트에 A2A task in-memory store 추가.

## 테스트
- 파일: `test/dev_web_server_test.dart`
  - `a2a` 비활성 상태에서 RPC endpoint `404` 검증.
  - `a2a` 활성 상태에서 `message:send` 및 `tasks:get` 왕복 동작 검증.

## 검증
- `dart analyze lib/src/dev/web_server.dart test/dev_web_server_test.dart` : PASS
- `dart test test/dev_web_server_test.dart` : PASS

## 결과
- Dev Web 서버의 `--a2a` 모드가 card discovery뿐 아니라 실제 RPC 호출까지 처리 가능.
