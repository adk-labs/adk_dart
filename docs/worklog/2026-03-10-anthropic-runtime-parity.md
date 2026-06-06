# 2026-03-10 Anthropic Runtime Parity

## Scope

Replaced the placeholder Anthropic runtime path with a real transport-backed
messages implementation and added streaming accumulation parity for text and
tool-use responses.

## Work Units

### 1. Native Anthropic transport

- Added a transport abstraction plus default HTTP implementation in
  `lib/src/models/anthropic_llm.dart`.
- The adapter now resolves:
  - `ANTHROPIC_API_KEY`
  - `ANTHROPIC_BASE_URL`
  - `ANTHROPIC_VERSION`
- Non-stream requests now call the Anthropic Messages API instead of returning a
  synthetic echo response.

### 2. Streaming response accumulation

- Added SSE parsing for Anthropic streaming responses.
- Text deltas now emit partial `LlmResponse` chunks.
- Tool-use JSON deltas now accumulate by block index and are emitted only in the
  final aggregated response.
- Final responses now carry usage metadata assembled from `message_start` and
  `message_delta` events.

### 3. Regression coverage

- Added `test/anthropic_runtime_parity_test.dart`.
- Covered:
  - non-stream runtime transport behavior
  - streaming text partial + final aggregation
  - streaming tool-use argument accumulation

## Verification

- `dart analyze lib/src/models/anthropic_llm.dart test/anthropic_runtime_parity_test.dart`
- `dart test test/anthropic_runtime_parity_test.dart`
