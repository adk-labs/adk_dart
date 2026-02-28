## 2026.2.28

- Switched package versioning scheme to date-based `YYYY.M.D`.
- Expanded `adk web` / `adk api_server` parity surface with bundled `/dev-ui` serving and broader API route compatibility.
- Hardened MCP transport/session behavior through `adk_mcp` integration updates and related tests.
- Added runtime gap audit document for remaining non-functional/default-unwired features.

## 0.1.2

- Added package topics metadata on pub.dev to improve discoverability.

## 0.1.1

- Expanded Python parity coverage across evaluator workflows and remote code executor paths.
- Added parity ports for model contracts and toolset stacks, including Google API, Pub/Sub, and OpenAPI integrations.
- Added Spanner, Bigtable, and BigQuery client/toolset parity layers with vector store and metadata/query support.
- Added session schema/migration utilities and missing shared utility modules.

## 0.1.0

- Bootstrap `adk_dart` package as an ADK core runtime port (based on `ref/adk-python`).
- Added core agent/session/event/tool/model abstractions and execution flow.
- Added `Runner` / `InMemoryRunner` with async invocation path.
- Added function-call orchestration in LLM flow.
- Added baseline tests for event behavior, session service, and runner flow.
