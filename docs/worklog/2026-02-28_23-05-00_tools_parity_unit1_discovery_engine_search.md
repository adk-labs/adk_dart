# Tools Parity Work Unit 1: DiscoveryEngineSearchTool

## Scope
- Target: `DiscoveryEngineSearchTool`
- Goal: align runtime behavior with Python-style default Discovery Engine search flow when explicit handler is not injected.

## Changes
- Added default Discovery Engine API execution path in `lib/src/tools/discovery_engine_search_tool.dart`.
- Added request/response model types for injectable HTTP transport and API error handling.
- Added default Google access token resolution utility in `lib/src/tools/_google_access_token.dart`.
  - Environment token keys
  - `gcloud auth application-default print-access-token`
  - GCP metadata server fallback
- Updated `DiscoveryEngineSearchTool.discoveryEngineSearch()` control flow:
  - Uses injected `searchHandler` when present.
  - Falls back to default API path when handler is absent.
  - Returns structured error payloads for handler/API failures.
- Added/updated parity tests for:
  - handler error path
  - no-handler default path error propagation
  - default API request shape (`contentSearchSpec.searchResultMode = CHUNKS`)
  - result normalization with `structData.uri` precedence.

## Validation
- Command:
  - `dart test test/tools_search_grounding_parity_test.dart`
- Result:
  - All tests passed.

## Notes
- This unit keeps backward-compatible structured return payloads (`status`, `error_message`) while enabling default API execution parity.
