# Tools Parity Work Unit 5: Google API Tooling

## Scope
- Targets:
  - `lib/src/tools/google_api_tool/google_api_tool.dart`
  - `lib/src/tools/google_api_tool/google_api_toolset.dart`
  - `lib/src/tools/google_api_tool/googleapi_to_openapi_converter.dart`
- Goal: align runtime behavior with Python `google_api_tool` path by delegating execution through OpenAPI `RestApiTool` flow.

## Changes
- Reworked `GoogleApiTool` to support wrapper mode over `RestApiTool`.
  - Added `GoogleApiTool.fromRestApiTool(...)` constructor.
  - Wrapper path now delegates declaration and execution to `RestApiTool`.
  - Service account auth now uses OpenAPI auth helper binding (`serviceAccountSchemeCredential`) instead of string sentinel auth scheme.
- Reworked `GoogleApiToolset` to load via `OpenAPIToolset` pipeline.
  - Converted discovery/OpenAPI spec once, then wraps parsed `RestApiTool` instances as `GoogleApiTool`.
  - Preserves optional `requestExecutor` injection via adapter to `RestApiRequestExecutor`.
  - Uses OpenID auth scheme derived from OpenAPI spec (scope behavior aligned to Python first-scope selection).
- Improved `GoogleApiToOpenApiConverter` parity.
  - Added built-in Google Discovery fetch fallback:
    - `https://www.googleapis.com/discovery/v1/apis/{api}/{version}/rest`
  - Fixed required-field propagation bug in schema conversion:
    - required status is now read from source property definition.

## Behavior Impact
- Tool execution path for Google API toolsets now uses mature OpenAPI request assembly/auth/error handling.
- Header/cookie/body/query/path parameter handling, required-default injection, and response normalization are inherited from `RestApiTool` path.
- Discovery conversion works out-of-the-box without mandatory injected fetcher.

## Tests
- Updated `test/google_api_tool_parity_test.dart` for service-account auth scheme shape.

## Validation
- Commands:
  - `dart test test/google_api_tool_parity_test.dart`
  - `dart analyze lib/src/tools/google_api_tool ...` (targeted set from this phase)
  - `dart test test/tools_search_grounding_parity_test.dart test/toolbox_toolset_parity_test.dart test/bigquery_parity_test.dart test/apihub_tool_parity_test.dart test/google_api_tool_parity_test.dart`
- Result:
  - All tests passed.
  - No analyzer issues in targeted files.
