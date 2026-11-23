# 2026-11-23 Upstream Parity Sync (`2026.11.23` / `adk-python` `2.15.0`)

## Upstream Range
- `adk-python`: `c81876a49911745248f2b774c02770ed211ff460..4d9e2c75f92305b335f8e66f8b4a8ea99f13017f` (`v2.15.0` baseline)
- `adk-web`: `4b7d11542b2a5540213d0578d733fae86505c024` (`v1.0.8`, no new commits; `main-PJ4DBNMP.js` already synced)

## Task-Unit Commits
1. `e260da81` — `fix(langchain): keep wrapped tool name and description in LangchainTool.fromConfig`
   - `f578fcd2d`: Treated empty `name`/`description` strings as omitted in `LangchainTool` and `LangchainTool.fromConfig`, preserving wrapped tool metadata (`lib/src/tools/langchain_tool.dart`).
   - Tests: `test/langchain_crewai_tool_parity_test.dart` (`10/10` passed).
2. `3bb795ed` — `feat(discovery_engine): add GroundingPlugin for grounding verification`
   - `9efe12527`: Added `GroundingPlugin` (`lib/src/integrations/discovery_engine/plugin.dart`), `Fact`, `GroundingClient`, `GroundingLimits.maxFactChars`, and `GroundingResult.copyWith` (`lib/src/integrations/discovery_engine/types.dart`, `check_grounding_client.dart`, `discovery_engine.dart`).
   - Tests: `test/upstream_nov23_discovery_engine_grounding_plugin_test.dart` (`34/34` passed; `62/62` with Nov 19 integrations suite).
3. `e6fe5b00` — `feat(fsspec): support Azure artifact metadata and tighten S3 metadata checks`
   - `481e1b2f1`, `4d9e2c75f`: Added `AzureBackendAdapter` (`abfs://`, `abfss://`, `az://`) with metadata support, `adlfs` version checks, and conflict handling; tightened `S3BackendAdapter` metadata key/value validation and encoding (`lib/src/integrations/fsspec/backends.dart`, `fsspec_artifact_service.dart`, `fsspec.dart`).
   - Tests: `test/upstream_nov23_fsspec_azure_s3_metadata_test.dart` (`39/39` passed; `145/145` across fsspec & artifact suites).

## Release
- Version: `2026.11.23` (`adkVersion = '2.15.0'`)
- Packages: `adk_mcp`, `adk_dart`, `adk_litertlm`, `flutter_adk`, `adk`
