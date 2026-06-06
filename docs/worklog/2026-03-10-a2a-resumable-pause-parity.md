# 2026-03-10 A2A Resumable Pause Parity

## Scope

Aligned resumable runner pause behavior with the latest Python flow logic so a
resumable invocation stays paused when the long-running signal is still present
in either of the last two invocation events.

## Work Units

### 1. Base flow pause semantics

- Updated `lib/src/flows/llm_flows/base_llm_flow.dart`.
- The resumable pause gate now checks the last two current-invocation events
  instead of only the last event.
- This prevents the runner from continuing the model loop immediately after a
  long-running function response arrives.

### 2. Regression coverage

- Added runner coverage for the sequence:
  - user message
  - long-running function call
  - matching function response
- The test asserts the resumable runner emits no new events and does not call
  the model again while the invocation should remain paused.

## Verification

- `dart analyze lib/src/flows/llm_flows/base_llm_flow.dart test/runner_flow_test.dart`
- `dart test test/runner_flow_test.dart -n "resumable app resolves invocationId from function response call id|resumable app stays paused when a long-running call is followed by a function response"`
