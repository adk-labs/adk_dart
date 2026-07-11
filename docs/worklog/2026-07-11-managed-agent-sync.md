# 2026-07-11 Managed Agent Sync

## 기준

- `adk-python`: `57e1ba66`

## 작업 단위

### 1. ManagedAgent Schema & Telemetry/Session Serialization

- 작업 내용:
  - `LlmResponse` 및 `Event` 클래스에 `environmentId` 필드를 추가하고 serialization/deserialization 로직 (`sqlite_session_service.dart`, `tracing.dart`)에 `environment_id`를 연동.
  - `LlmRequest` 클래스에 `isManagedAgent` 필드를 추가해 Managed Agent 호출 여부를 판별할 수 있도록 함.
- 작업 이유: Python의 `Event` 및 `LlmResponse` 구조(GCP Managed Agents API의 interaction/environment ID 지원)와의 동기화 및 SQLite 세션 영속화 연동.

### 2. Grounding Tool Constraints Bypass

- 작업 내용: `google_search_tool.dart` 및 `url_context_tool.dart`에서 `llmRequest.isManagedAgent`가 `true`일 때 클라이언트 측 constraints/checks를 우회하도록 설정.
- 작업 이유: Managed Agent의 경우 구글 검색 및 URL 컨텍스트 처리가 서버 사이드에서 직접 수행되기 때문에 클라이언트 단의 제약을 건너뛰어야 함.

### 3. State Recovery Integration

- 작업 내용: `interactions_processor.dart` 내 `findPreviousInteractionState` 헬퍼가 `previousInteractionId` 뿐만 아니라 `environmentId`를 포함한 레코드 `(String? previousInteractionId, String? environmentId)`를 반환하도록 리팩토링.
- 작업 이유: 이전 인터랙션 세션의 샌드박스 환경(Environment ID)을 그대로 유지하면서 후속 인터랙션을 수행할 수 있도록 세션 히스토리 복구를 지원하기 위함.

### 4. ManagedAgent 및 RemoteMcpServer 구현

- 작업 내용:
  - `BaseAgent`를 상속하는 `ManagedAgent` 구현 (`lib/src/agents/managed_agent.dart`). `streamCreateInteraction`을 호출하여 백엔드 인터랙션을 처리하고 SSE/NONE 모드에 맞추어 응답을 스트리밍.
  - 서버 사이드 MCP 처리를 지정하기 위한 `RemoteMcpServer` 구성 클래스 구현 (`lib/src/tools/remote_mcp_server.dart`).
  - `adk_core.dart` 및 `adk_dart.dart`에 두 기능을 export 처리.
  - `env_utils.dart`에 `isEnterpriseModeEnabled` 환경 변수 판별 헬퍼 추가.
- 작업 이유: Python `_managed_agent.py` 및 `_remote_mcp_server.py` 기능의 Dart 포팅 완결.

### 5. Parity Tests

- 작업 내용: `test/managed_agent_parity_test.dart` 추가. 생성자 필드 주입, 도구 분석(Mcp / UrlContext), 스트리밍/비스트리밍(SSE/NONE) 응답 및 API 예외 전파 테스트 추가.
- 작업 이유: 기능 포팅에 따른 런타임 신뢰성 및 기존 기능 회귀(Regression) 방지.

## 이번 작업에서 남긴 Gap

- Python의 `RemoteMcpServer`와 관련된 복잡한 header_provider 등 비동기 바인딩 검증은 기본적인 dynamic header 헬퍼만 포함시켰으며, 실제 백엔드 연동 시 세부 헤더 명세에 대한 추가 튜닝이 필요할 수 있음.

## 검증

- `dart analyze lib test`
- `dart test test/managed_agent_parity_test.dart`
- `dart test` 전체 테스트 스위트 통과 (`1365` pass).
