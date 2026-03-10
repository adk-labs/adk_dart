# 2026-03-10 A2A Long-Running Finalization Parity

## Scope

Ported the missing A2A long-running function extraction/finalization layer so
intermediate events no longer leak long-running function call/response payloads
and the executor emits a final `input_required` / `auth_required` task event.

## Work Units

### 1. Long-running accumulator

- Added `lib/src/a2a/converters/long_running_functions.dart`.
- The helper now:
  - tracks long-running function calls by ID
  - collects matching function responses
  - strips those parts from intermediate ADK events
  - synthesizes the final A2A task event with accumulated parts

### 2. Executor integration

- Updated `lib/src/a2a/executor/a2a_agent_executor.dart` to:
  - process each ADK event through `LongRunningFunctions`
  - feed the stripped event into the normal A2A converter path
  - prefer the synthesized long-running final event over the legacy
    aggregator-completed final event
  - still preserve failure precedence

### 3. Regression coverage

- Added executor tests for:
  - final `input_required` event generation
  - final `auth_required` event generation
  - preserving long-running function responses only on the final event

## Verification

- `dart analyze lib/src/a2a/converters/long_running_functions.dart lib/src/a2a/executor/a2a_agent_executor.dart test/a2a_parity_test.dart`
- `dart test test/a2a_parity_test.dart`
