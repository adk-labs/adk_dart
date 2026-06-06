# 2026-03-10 A2A Dev Server Resume Wiring

## Scope

Fixed the dev web server A2A `message/send` path so resume requests reuse the
stored task snapshot instead of always behaving like fresh requests.

## Work Units

### 1. Stored task reconstruction

- Added JSON-to-A2A parsing helpers in `lib/src/dev/web_server.dart` for:
  - `A2aTask`
  - `A2aTaskStatus`
  - `A2aArtifact`
  - wire task-state strings

### 2. Resume request propagation

- Updated `_executeA2aMessageSend(...)` to:
  - load the stored task by `taskId`
  - reconstruct `currentTask`
  - reuse the stored `contextId` when the incoming request omits it
  - pass `currentTask` into `A2aRequestContext`

### 3. Response identity normalization

- Normalized `message/send` responses so returned A2A messages always include
  `taskId` and `contextId`, even when the underlying status message omitted
  them.

### 4. End-to-end regression coverage

- Added a dev server test proving that:
  - the first request stores an `input_required` task
  - the second request with the same `taskId` but no function response does not
    re-run the agent
  - the stored `contextId` is reused
  - the executor returns the missing-function-response message

## Verification

- `dart analyze lib/src/dev/web_server.dart test/dev_web_server_test.dart`
- `dart test test/dev_web_server_test.dart -n "handles a2a message send and task get rpc routes|reuses stored a2a currentTask on message/send resume requests"`

## Deferred

- This batch does not yet port Python's full long-running function extraction
  and finalization layer.
- The next A2A parity step remains the deeper long-running/durable runtime path.
