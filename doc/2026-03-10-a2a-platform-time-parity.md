# 2026-03-10 A2A Platform Time Parity

## Scope

Aligned the remaining Dart A2A protocol timestamp defaults with the shared
platform time abstraction used in the latest Python parity updates.

## Work Units

### 1. A2A protocol timestamp defaults

- Updated `lib/src/a2a/protocol.dart` so `A2aTaskStatus` uses
  `getUtcNow().toIso8601String()` instead of `DateTime.now()`.
- This brings status timestamps under the same overridable time provider used
  elsewhere in the runtime.

### 2. Local A2A router timestamps

- Updated `lib/src/a2a/a2a_message.dart` so in-memory routed `A2AMessage`
  instances also use `getUtcNow()`.

### 3. Regression coverage

- Added tests proving both `A2aTaskStatus` and `A2AMessage` respect
  `setTimeProvider(...)`.

## Verification

- `dart analyze lib/src/a2a/protocol.dart lib/src/a2a/a2a_message.dart test/a2a_parity_test.dart`
- `dart test test/a2a_parity_test.dart`
