# 2026-05-01 Flutter Example Latest Surface Update

Reference baseline:

- `ref/adk-python`: `8788d1c2`
- Latest local parity baseline: `e95906c`

## Work Units

### 1. Flutter-Safe Built-In Tool Example

- Work: Added a `URL Context` example to the Flutter sample app using the exported `urlContext` built-in tool.
- Reason: Recent ADK parity work added model-side URL context support to the web-safe `adk_core` surface, but the Flutter example app still only demonstrated FunctionTool, workflow agents, MCP, and Skills.

### 2. Flutter Export Surface Coverage

- Work: Exported `AgentTool` from `adk_core` and added Flutter package tests for `AgentTool`, `UrlContextTool`, `VertexAiSearchTool`, and `VertexRagRetrievalTool`.
- Reason: These APIs are web-safe and useful for Flutter apps. Without an export/test, Flutter users could not rely on the single `package:flutter_adk/flutter_adk.dart` import for the latest tool surface.

### 3. Skill Registry Example Coverage

- Work: At the time, extended the Skills example with an in-memory `SkillRegistry`, a registry-only `briefing-translator` skill, and prompt guidance to call `search_skills` when inline skills are insufficient.
- Reason: The 2026-05-01 ADK Skills behavior included registry-backed discovery/loading. The previous Flutter example only showed fixed inline skill listing and loading.
- Current status: Superseded by the 2026-05-11 sync. Latest `adk-python` removed the registry search path, so the Flutter example now documents inline skills without `search_skills`.

### 4. Local Development Overrides

- Work: Added `adk_mcp` path overrides to `packages/flutter_adk` and `packages/flutter_adk/example`.
- Reason: Flutter package tests could not resolve unpublished local `adk_mcp ^2026.4.17` through the package-local override files. The root override is not inherited when testing nested packages directly.

### 5. Documentation

- Work: Updated `flutter_adk` package docs and Flutter example docs in English, Korean, Japanese, and Chinese.
- Reason: The supported platform matrix and included-example list needed to reflect built-in model tools, `AgentTool`, and the then-current Skills surface.

## Reviewed But Not Patched

- `VertexAiSearchTool` and `VertexRagRetrievalTool` were not added as default runnable example cards because they require user-specific Google Cloud resource IDs and project setup.
- MCP stdio remains outside the Flutter example because Web cannot spawn local processes; the example intentionally demonstrates Streamable HTTP MCP only.
- Directory-based skill loading remains documented as unsupported on Web; inline skills remain the cross-platform path.

## Verification

- Passed: `flutter test` in `packages/flutter_adk`
- Passed: `flutter test` in `packages/flutter_adk/example`
- Passed: `flutter analyze` in `packages/flutter_adk`
- Passed: `flutter analyze` in `packages/flutter_adk/example`
