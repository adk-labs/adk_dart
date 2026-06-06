# 2026-03-18 Latest Four-Day Parity Batch

## Scope

- Source: `ref/adk-python`
- Window: `2026-03-14` through `2026-03-18`
- Goal: apply concrete runtime and library parity changes that map cleanly to
  the Dart implementation surface.

## Work Units

### 1. Agent version rollback parity

- Removed the temporary `agent.version` runtime expectation from tests.
- Ignored legacy config `version` keys instead of treating them as unknown
  extras, preserving compatibility for older config files.

### 2. Database stale-session parity

- Moved stale-writer detection to the concrete storage backends.
- Added storage revision markers to `Session`.
- Allowed marker-less sessions with harmless timestamp drift to append when the
  latest persisted event revision still matches the in-memory session.

### 3. Vertex AI usage metadata parity

- Stored `usageMetadata` under internal `custom_metadata` keys because the
  Vertex AI session service does not persist it natively.
- Restored `usageMetadata` on read and stripped internal keys from
  user-visible `customMetadata`.

### 4. LiteLLM Anthropic thinking blocks parity

- Parsed Anthropic `thinking_blocks` into thought parts while preserving
  signatures.
- Rebuilt `thinking_blocks` for Anthropic models when serializing thought parts
  back to LiteLLM payloads.

### 5. Spanner database role parity

- Added `database_role` / `databaseRole` to `SpannerToolSettings`.
- Threaded the setting into database handle creation and query execution.

## Validation

- Targeted `dart analyze` on changed files.
- Targeted tests for:
  - agent config / clone / telemetry rollback
  - session persistence and Vertex AI session service behavior
  - LiteLLM reasoning and Anthropic thinking block handling
  - Spanner settings and query execution
