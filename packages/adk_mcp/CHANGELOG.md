# Changelog

## Unreleased

## 2026.7.11

- Bumped package version to `2026.7.11`.
- Synced MCP package release with the `adk_dart` `2026.7.11` rollout.
- Added ADK 2.0 support including Managed Agent and Remote MCP Server
  integration for server-side tool execution via the Interactions API.

## 2026.6.6

- Bumped package version to `2026.6.6`.
- Synced MCP package release with the `adk_dart` `2026.6.6` rollout.
- Aligned the non-IO stdio stub API with the IO implementation for task,
  progress, metadata, and notification helpers.
- Hardened stdio timeout cancellation coverage to avoid timing-dependent false
  negatives.
- ADK-facing MCP session cleanup and toolset handling updates landed in the main
  `adk_dart` MCP integration layer.

## 2026.4.17

- Bumped package version to `2026.4.17`.
- Synced MCP package release with the `adk_dart` `2026.4.17` rollout.

## 2026.3.21

- Bumped package version to `2026.3.21`.
- Added MCP client capability override support during initialization.
- Added ADK-facing sampling callback/capability wiring coverage through the `adk_dart` MCP toolset stack.
- Synced MCP package release with the `adk_dart` `2026.3.21` rollout.

## 2026.3.13

- Bumped package version to `2026.3.13`.
- Synced MCP package release with the `adk_dart` `2026.3.13` rollout.

## 2026.3.6

- Bumped package version to `2026.3.6`.
- Synced MCP package release with the `adk_dart` `2026.3.6` rollout.

## 2026.3.2+4

- Bumped package version to `2026.3.2+4`.
- Synced MCP package release with the `adk_dart` `2026.3.2+4` rollout.

## 2026.3.2+3

- Bumped package version to `2026.3.2+3`.
- Synced MCP package release with the `adk_dart` `2026.3.2+3` rollout.

## 2026.3.2+2

- Bumped package version to `2026.3.2+2`.
- Synced MCP package release with the `adk_dart` `2026.3.2+2` rollout.

## 2026.3.2+1

- Bumped package version to `2026.3.2+1`.
- Synced MCP package release with the `adk_dart` `2026.3.2+1` build rollout.

## 2026.3.2

- Bumped package version to `2026.3.2`.
- Synced MCP package release with the `adk_dart` `2026.3.2` rollout.

## 2026.3.1

- Bumped package version to `2026.3.1`.
- Synced MCP package release with the `adk_dart` `2026.3.1` rollout.
- Carried forward MCP transport/session hardening behavior covered by existing tests.

## 2026.2.28

- Introduced date-based versioning format `YYYY.M.D`.
- Added MCP protocol hardening updates aligned with the 2025-11-25 spec workstream.
- Expanded remote/stdio lifecycle and request handling test coverage.
