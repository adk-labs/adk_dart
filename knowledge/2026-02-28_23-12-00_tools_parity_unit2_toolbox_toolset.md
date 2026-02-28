# Tools Parity Work Unit 2: ToolboxToolset

## Scope
- Target: `ToolboxToolset`
- Goal: align lifecycle semantics with Python implementation, especially fail-fast initialization and delegate construction.

## Changes
- Updated `lib/src/tools/toolbox_toolset.dart` to fail at construction time when toolbox integration is missing.
  - Previous behavior: deferred failure until `getTools()`.
  - New behavior: constructor throws `StateError` if neither explicit delegate nor registered default delegate factory exists.
- Added global registration hooks for runtime integration:
  - `ToolboxToolset.registerDefaultDelegateFactory(...)`
  - `ToolboxToolset.clearDefaultDelegateFactory()`
- Added default delegate construction path that forwards all constructor arguments to the registered factory:
  - `serverUrl`, `toolsetName`, `toolNames`, `authTokenGetters`, `boundParams`, `credentials`, `additionalHeaders`, `additionalOptions`.

## Tests
- Updated/added parity tests in `test/toolbox_toolset_parity_test.dart`:
  - constructor fail-fast when integration is missing
  - explicit delegate path behavior
  - registered default factory path and full argument forwarding

## Validation
- Command:
  - `dart test test/toolbox_toolset_parity_test.dart`
- Result:
  - All tests passed.

## Notes
- This unit preserves pluggable Dart integration while matching Python’s constructor-time validation expectation.
