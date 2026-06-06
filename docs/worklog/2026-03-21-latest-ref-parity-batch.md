# 2026-03-21 Latest Ref Parity Batch

Range reviewed:
- `ref/adk-python` `31b005c3..4b677e73`

Applied work units

1. Skills feature parity
- Added `FeatureName.environmentSimulation`, `FeatureName.pluggableAuth`, and `FeatureName.snakeCaseSkillName`.
- Enabled `Frontmatter.name` validation to accept `snake_case` behind `SNAKE_CASE_SKILL_NAME`.
- Updated both VM and web skill parsers.

2. Token compaction safety parity
- Prevented token-threshold compaction from compacting pending function-call events.
- Prevented compaction split points that would orphan retained function responses from their matching calls.
- Added regression tests for pending-call and retained-response cases.

3. Discovery Engine structured datastore parity
- Added `SearchResultMode`.
- Added automatic `CHUNKS -> DOCUMENTS` fallback on structured datastore errors.
- Added explicit document-mode support and document-result parsing.

4. A2A metadata and lifecycle parity
- Added `A2aArtifact.metadata`.
- Added `EventActions` JSON serialization/deserialization helpers.
- Preserved `EventActions` through A2A message/status/artifact metadata round-trips.
- Added direct converters for status-update and artifact-update events.
- Added `lifespan` callbacks to `toA2a()` / `A2aApplication`.

5. Import-path compatibility
- Added compatibility wrapper exports for:
  - `src/integrations/crewai/crewai_tool.dart`
  - `src/integrations/langchain/langchain_tool.dart`

Validation
- `dart analyze` on changed files: passed
- `dart test` passed:
  - `test/skills_models_test.dart`
  - `test/compaction_parity_test.dart`
  - `test/tools_search_grounding_parity_test.dart`
  - `test/a2a_parity_test.dart`
  - `test/remote_a2a_agent_parity_test.dart`

Reviewed but not patched
- A2A experimental warning suppression: Dart wrapper does not emit the warning, so there was no functional gap to close.
- `DatabaseSessionService` read-only wrapper change: current Dart services already enforce read-only behavior at the concrete service layer; no additional wrapper fix was needed in this batch.
- Bash async subprocess refactor: Dart already uses async process execution and did not have the Python-specific blocking issue.
