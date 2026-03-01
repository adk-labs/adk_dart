# Sessions Vertex API Parity Work Unit (2026-03-01 09:49:16)

## Scope
- Dart target:
  - `lib/src/sessions/vertex_ai_session_service.dart`
  - `test/session_persistence_services_test.dart`
- Python reference:
  - `ref/adk-python/src/google/adk/sessions/vertex_ai_session_service.py`
  - `ref/adk-python/tests/unittests/sessions/test_vertex_ai_session_service.py`

## Parity gaps addressed
1. `VertexAiSessionService` was in-memory delegate only.
   - Python uses real Vertex session/event APIs.
   - Dart previously proxied to `InMemorySessionService`.
2. Missing API model conversion path.
   - Python converts API session/event payloads to ADK `Session`/`Event` and back.
   - Dart had no API payload encoding/decoding for sessions/events.
3. Missing ownership and filter behavior in get/list flow.
   - Python verifies session ownership and supports event filtering behavior.

## Implemented changes
1. Introduced API client abstraction for Vertex session runtime.
   - Added `VertexAiSessionApiClient` interface.
   - Added default `VertexAiSessionHttpApiClient` implementation.
   - Added pluggable `VertexAiSessionApiClientFactory` for tests and custom transports.
2. Added HTTP transport and endpoint shaping.
   - Implemented create/get/list/delete session operations.
   - Implemented list/append event operations.
   - Added auth header flow via access token provider and express-mode API key query support.
3. Replaced in-memory delegation with API-backed service methods.
   - `createSession/getSession/listSessions/deleteSession/appendEvent` now use API client.
   - `getSession` keeps Python-compatible owner check and event retrieval behavior.
4. Added API payload serialization/parsing helpers.
   - Event/content/part mapping (`snake_case` fields, base64 for binary fields).
   - Actions/event_metadata mapping.
   - API session/event JSON -> ADK model conversion.

## Tests updated
- `test/session_persistence_services_test.dart`
  - Replaced old proxy-style vertex tests with injected fake API client tests.
  - Added create/get/list/append/delete lifecycle verification.
  - Added missing-session null behavior verification.
  - Added user-provided session id rejection verification.
  - Added owner mismatch rejection verification.

## Validation
- `dart analyze lib/src/sessions/vertex_ai_session_service.dart test/session_persistence_services_test.dart`: passed.
- `dart test test/session_persistence_services_test.dart`: `26 passed, 0 failed`.
