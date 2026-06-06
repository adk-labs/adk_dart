# Parity Unit: Workflow Replay Sequence Barrier

- Date: 2026-06-06
- Commit: `9335443 feat: add workflow replay sequence barrier`
- Reference: `ref/adk-python` workflow replay utilities
- Scope:
  - `lib/src/workflow/workflow.dart`
  - `test/workflow_runtime_parity_test.dart`

## Background

Python v2 workflow replay uses a chronological barrier so replayed node events are consumed in the original sequence. Dart had workflow event-history rehydration and silent replay fast-forward support, but did not expose the equivalent replay ordering helper.

## Implementation

- Added public `ReplaySequenceBarrier`.
- Unknown replay keys pass through immediately.
- The first known key is released on construction.
- Later known keys are released only after the expected prior key advances.
- Out-of-order `advance(...)` calls are ignored until the expected key is reached.

## Tests

- Added regression coverage for:
  - first-key initialization
  - blocking and unblocking known replay keys
  - ignoring out-of-order advance
  - unknown-key passthrough

## Verification

- `dart analyze lib/src/workflow/workflow.dart test/workflow_runtime_parity_test.dart`: PASS
- `dart test test/workflow_runtime_parity_test.dart`: PASS, 72 passed
- `dart analyze lib test`: PASS with existing info-level lints
- `dart test`: PASS, 1321 passed, 3 skipped

## Remaining Gap

- This closed the standalone replay sequence barrier utility baseline.
- Full replay sequence runtime integration with nested workflow HITL resume remains separate work.
