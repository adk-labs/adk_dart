# Parity Unit: LlmAgent outputKey Callback Visibility

- Date: 2026-06-06
- Commit: `8be6b1a test: cover output key callback visibility`
- Reference: `ref/adk-python/tests/unittests/agents/test_output_key_visibility.py`
- Scope:
  - `test/llm_agent_output_state_test.dart`

## Background

Python now verifies that `output_key` state is visible during agent lifecycle callbacks and to later sequential agents. Dart already had the correct runner/event ordering, but the behavior was not pinned with equivalent tests.

## Implementation

- No production code change was required.
- Added a flow-backed test `LlmAgent` to mirror Python's AutoFlow monkeypatch style without depending on a live model backend.
- Added callback visibility tests for async and live run paths.

## Tests

- Added regression coverage for:
  - same-agent `afterAgentCallback` sees the state written by `outputKey`
  - live-run `afterAgentCallback` sees the state written by `outputKey`
  - next `SequentialAgent` child sees previous child `outputKey` state before its callback

## Verification

- `dart analyze test/llm_agent_output_state_test.dart`: PASS
- `dart test test/llm_agent_output_state_test.dart`: PASS, 7 passed
- `dart analyze lib test`: PASS with existing info-level lints
- `dart test`: PASS, 1324 passed, 3 skipped

## Remaining Gap

- This closed the `output_key` callback visibility parity gap.
- No known production runtime change was needed for this behavior.
