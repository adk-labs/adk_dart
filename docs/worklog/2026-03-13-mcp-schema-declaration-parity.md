# 2026-03-13 MCP Schema Declaration Parity

## Scope

- align `McpTool.getDeclaration()` with Python's JSON-schema function declaration behavior
- preserve existing non-feature-gated declaration behavior
- add regression coverage for populated and empty output schemas

## Changes

### 1. JSON schema declaration path

- when `FeatureName.jsonSchemaForFuncDecl` is enabled, `McpTool` now builds its
  declaration through the shared JSON-schema helper
- the MCP input schema remains the declaration parameter schema
- non-empty MCP output schema is attached through the shared response-schema
  extension path

### 2. Empty output schema handling

- empty MCP output schemas are skipped instead of being serialized as an empty
  response schema payload
- this matches the Python parity expectation that an empty output schema is not
  treated as a meaningful declaration response schema

## Verification

- `dart analyze` on changed files
- `dart test test/mcp_resource_and_tool_test.dart`
