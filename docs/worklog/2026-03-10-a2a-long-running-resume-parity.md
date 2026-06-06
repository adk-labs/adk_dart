# 2026-03-10 A2A Long-Running Resume Parity

## Scope

Aligned the Dart A2A executor with the latest Python long-running resume
behavior for resumed `inputRequired` and `authRequired` tasks.

## Work Units

### 1. Resume input validation

- Added resumed-task validation in
  `lib/src/a2a/executor/a2a_agent_executor.dart`.
- If the current task is `inputRequired` or `authRequired`, the executor now
  requires a function-response data part before resuming the runner.
- When the response is missing, the executor returns a final status update with
  the same task state and the Python-matching message:
  `It was not provided a function response for the function call.`

### 2. Event ordering and metadata parity

- Moved resume validation ahead of the synthetic `working` event so resumed
  requests that are still waiting on function input do not emit `working`.
- Added shared invocation metadata helper and now attach:
  - `adk_app_name`
  - `adk_user_id`
  - `adk_session_id`
  - `adk_agent_executor_v2`
- Applied that metadata to both the `working` event and the final terminal
  event.

### 3. Targeted regression coverage

- Added executor tests for:
  - resumed `inputRequired` requests without a function response
  - resumed `authRequired` requests without a function response
  - resumed requests with a valid function response
  - invocation metadata on `working` and final events

## Verification

- `dart analyze lib/src/a2a/executor/a2a_agent_executor.dart test/a2a_parity_test.dart`
- `dart test test/a2a_parity_test.dart`

## Deferred

- This batch does not yet port the full Python `LongRunningFunctions`
  buffering/re-emission path.
- Remaining larger A2A parity work is centered on deeper durable runtime
  semantics beyond the user-input resume guardrail added here.
