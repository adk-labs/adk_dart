# Memory Parity Follow-up Work Unit (2026-03-01 09:42:33)

## Scope
- Dart target:
  - `lib/src/memory/vertex_ai_memory_bank_service.dart`
  - `test/vertex_memory_services_parity_test.dart`
- Python reference:
  - `ref/adk-python/src/google/adk/memory/vertex_ai_memory_bank_service.py`

## Parity gaps addressed
1. Event payload binary field serialization mismatch.
   - Python serializes content with JSON-mode encoding (binary fields base64 strings).
   - Dart forwarded `List<int>` for `thought_signature` and `inline_data.data`.
2. Default client behavior mismatch.
   - Python path constructs real client and fails if not configured.
   - Dart silently defaulted to in-memory fallback client when not configured.

## Implemented changes
1. Base64 serialization alignment for memory bank content payloads.
   - `thought_signature` now serialized as base64 string.
   - `inline_data.data` now serialized as base64 string.
   - Added normalization pass for pre-shaped event payloads to ensure base64 conversion.
2. Default factory strictness alignment.
   - Removed implicit `InMemoryVertexAiMemoryBankApiClient` fallback from default client factory.
   - Now throws configuration `ArgumentError` unless `project/location` or `expressModeApiKey` is provided.
   - Explicit in-memory behavior remains available via custom `clientFactory` injection in tests.

## Tests added/updated
- `test/vertex_memory_services_parity_test.dart`
  - Updated in-memory test setup to provide explicit in-memory client factory.
  - Added payload assertions for base64 `thought_signature` and `inline_data.data`.
  - Added default-configuration failure test (search path triggers client creation).

## Validation
- `dart analyze` for modified memory files/tests: passed.
- Targeted memory tests: passed.
