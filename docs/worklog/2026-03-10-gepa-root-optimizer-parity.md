# 2026-03-10 GEPA Root Optimizer Parity

## Scope

Added a GEPA-style root-agent prompt optimizer surface so the Dart runtime now
has a dedicated optimizer that reflects on train examples, proposes prompt
updates, evaluates them, and returns GEPA-style result metadata.

## Work Units

### 1. Optimizer surface

- Added `lib/src/optimization/gepa_root_agent_prompt_optimizer.dart`.
- Introduced:
  - `GepaRootAgentPromptOptimizerConfig`
  - `GepaRootAgentPromptOptimizer`
  - `GepaRootAgentPromptOptimizerResult`
- Exported the new optimizer from `lib/adk_dart.dart`.

### 2. GEPA-style execution flow

- The optimizer now:
  - samples reflection minibatches from the train split
  - captures full eval data for reflection
  - asks an optimizer model for a revised root instruction
  - scores each candidate on the validation split
  - returns candidates sorted by validation score
  - records GEPA-style raw metadata including candidates, batches, and scores

### 3. Artifact persistence and tests

- Added optional `runDir` artifact persistence via `gepa_result.json`.
- Added regression coverage for:
  - candidate ranking and raw result metadata
  - persisted run artifacts when `runDir` is configured

## Verification

- `dart analyze lib/src/optimization/gepa_root_agent_prompt_optimizer.dart test/gepa_root_agent_prompt_optimizer_test.dart lib/adk_dart.dart`
- `dart test test/gepa_root_agent_prompt_optimizer_test.dart`
