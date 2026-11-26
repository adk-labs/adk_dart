# 2026-11-26 Upstream Parity Sync (`2026.11.26` / `adk-python` `2.15.1`)

## Upstream Range
- `adk-python`: `54fc37e5fab77f2cfc02fd02f8e6019d288d3920..03725e8c67ca27b2c07569797a0c18e867e0b217` (`v2.15.1` baseline)
- `adk-web`: `4b7d11542b2a5540213d0578d733fae86505c024` (`v1.0.8`, no new commits; `main-PJ4DBNMP.js` already synced)

## Task-Unit Commits
1. `a14f4e88` — `feat(cli): add pure Dart HttpAgentEngineRuntimesClient for Vertex AI Agent Engine`
   - Added pure Dart `HttpAgentEngineRuntimesClient` (`packages/adk/lib/src/cli/http_agent_engine_runtimes_client.dart`), exported via `cli.dart`, and wired into `cli_deploy.dart` for `adk deploy agent_engine --update_if_exists`.
   - Tests: `packages/adk/test/http_agent_engine_runtimes_client_e2e_test.dart` (`9/9` E2E passed; `98/98` across CLI deploy suites).
2. `d7bdc242` — `feat(fsspec): add pure Dart REST backends for GCS, S3 (SigV4), and Azure Blob`
   - Added `GcsFsspecFilesystem`, `S3FsspecFilesystem` (AWS SigV4), and `AzureBlobFsspecFilesystem` (SharedKey/SAS/Bearer) in `lib/src/integrations/fsspec/cloud_filesystems.dart`, wired into `urlToFs` / `FsspecArtifactService`.
   - Tests: `test/fsspec_cloud_filesystems_e2e_test.dart` (`5/5` E2E passed; `105/105` across fsspec suites).
3. `82553d5b` — `fix(plugins): expand credential redaction names and fix BQAA eval SQL tiebreakers and scoped system prompt`
   - `e3dbdc172`, `851b7707a`, `3e322e9a9`: Updated `lib/src/utils/credential_names.dart` and `lib/src/plugins/_bigquery_agent_analytics_eval_sql.dart`.
   - Tests: `test/upstream_nov26_plugins_bqaa_credentials_parity_test.dart` + 8 suites (`127/127` passed).
4. `b48f622a` — `fix(models,a2a): handle Claude 2026-10-21 sampling removal and propagate runner cancellation in A2A executor`
   - `1c384506e`, `50961696a`: Updated `lib/src/models/anthropic_llm.dart` and `lib/src/a2a/executor/a2a_agent_executor.dart`.
   - Tests: `test/upstream_nov26_anthropic_a2a_parity_test.dart` + 12 suites (`290/290` passed).
5. `cc940246` — `feat(telemetry): add gen_ai.client.inference.duration, skip history when capture is off, and support reasoning parts`
   - `8d064dc91`, `825a44c5d`, `0019b8658`: Updated `lib/src/telemetry/metrics.dart`, `_experimental_semconv.dart`, `tracing.dart`.
   - Tests: `test/upstream_nov26_telemetry_parity_test.dart` + 10 suites (`166/166` passed).
6. `b528cbfe` — `feat(optimization): add agent tree cloner and multi-objective GridSearchAgentOptimizer`
   - `d723cb87b`, `276b7e0e6`: Added `lib/src/optimization/agent_tree_cloner.dart`, `grid_search_agent_optimizer.dart`, feature `GRID_SEARCH_AGENT_OPTIMIZER`, and exports in `lib/adk_dart.dart`.
   - Tests: `test/upstream_nov26_optimization_grid_search_parity_test.dart` + 6 suites (`145/145` passed).

## Release
- Version: `2026.11.26` (`adkVersion = '2.15.1'`)
- Packages: `adk_mcp`, `adk_dart`, `adk_litertlm`, `flutter_adk`, `adk`
