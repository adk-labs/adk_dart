# Parity Work Unit: memory (2026-03-01)

## Scope
- Python reference
  - `ref/adk-python/src/google/adk/memory/base_memory_service.py`
  - `ref/adk-python/src/google/adk/memory/in_memory_memory_service.py`
  - `ref/adk-python/src/google/adk/memory/vertex_ai_memory_bank_service.py`
  - `ref/adk-python/src/google/adk/memory/vertex_ai_rag_memory_service.py`
- Dart target
  - `lib/src/memory/*`

## Gaps Found
1. `BaseMemoryService` default methods were behaviorally different.
- Python: `add_events_to_memory` / `add_memory` default to `NotImplementedError`.
- Dart (before): auto-synthesized sessions/events and performed writes.

2. `InMemoryMemoryService` mismatched explicit event ingest semantics.
- Python: `custom_metadata` argument is ignored in `add_events_to_memory`.
- Dart (before): merged `customMetadata` into stored events.
- Python: no `add_memory` override (unsupported via base default).
- Dart (before): implemented `addMemory` synthetic path.

3. Vertex Memory Bank event ingest payload shape diverged.
- Python sends `direct_contents_source.events[*].content` (structured content payload).
- Dart (before): flattened content to text placeholders (`[inline_data:...]`, `[file_data:...]`).

4. Vertex Memory Bank retrieval request shape diverged.
- Python uses `similarity_search_params: { search_query: query }`.
- Dart (before): sent `{ query: ... }`.

## Implemented Changes
1. `BaseMemoryService` parity alignment.
- Updated defaults to throw `UnsupportedError` with Python-equivalent messages for:
  - `addEventsToMemory(...)`
  - `addMemory(...)`

2. `InMemoryMemoryService` parity alignment.
- `addEventsToMemory(...)` now ignores `customMetadata`.
- Removed synthetic `addMemory(...)` override to inherit base unsupported behavior.
- `searchMemory(...)` now returns memory entries with Python-like output contract:
  - preserved `content` and `author`
  - `timestamp` from `formatTimestamp(...)`
  - no merged custom metadata payload from ingest options

3. Vertex Memory Bank structured content ingest.
- Refactored client API from text-based ingest to structured-event ingest:
  - `generateFromEvents(..., events: List<Map<String, Object?>>)`
- Added conversion helpers to preserve content structure:
  - `_contentToVertexJson(...)`
  - `_partToVertexJson(...)`
  - `_normalizeVertexGenerateEvent(...)`
- Service now sends `direct_contents_source.events` with full content payload.

4. Vertex Memory Bank retrieval request parity.
- HTTP payload now uses:
  - `similarity_search_params: { search_query: query }`

## Tests Updated
- `test/base_memory_service_default_test.dart`
- `test/memory_service_test.dart`
- `test/vertex_memory_services_parity_test.dart`

## Validation
- `dart analyze lib/src/memory/base_memory_service.dart lib/src/memory/in_memory_memory_service.dart lib/src/memory/vertex_ai_memory_bank_service.dart test/base_memory_service_default_test.dart test/memory_service_test.dart test/vertex_memory_services_parity_test.dart`
- `dart test test/base_memory_service_default_test.dart test/memory_service_test.dart test/vertex_memory_services_parity_test.dart test/tools_memory_artifacts_test.dart`

All listed checks passed after patching.
