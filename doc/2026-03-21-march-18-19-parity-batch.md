# March 18-19 Parity Batch

## Scope

- Source reports:
  - `reports/adk-python/2026-03-18.md`
  - `reports/adk-python/2026-03-19.md`
- Goal: reflect directly portable runtime/library changes in `adk_dart` and close concrete behavior gaps.

## Applied

### 1. Spanner admin parity

- Added experimental `SpannerAdminToolset`.
- Added admin client/runtime surface with override hooks:
  - `getSpannerAdminClient(...)`
  - `setSpannerAdminClientFactory(...)`
  - `resetSpannerAdminClientFactory()`
- Added tool functions:
  - `listInstances`
  - `getInstance`
  - `listInstanceConfigs`
  - `getInstanceConfig`
  - `listDatabases`
  - `createDatabase`
  - `createInstance`
- Wired admin runtime into:
  - `configureToolRuntimeBootstrap(...)`
  - `resetToolRuntimeBootstrap(...)`
  - `configureSpannerPubSubRuntime(...)`
  - `resetSpannerPubSubRuntime(...)`

## 2. Environment simulation rename parity

- Added `environment_simulation` compatibility exports on top of the existing `agent_simulator` implementation.
- Added renamed aliases for:
  - config
  - engine
  - factory
  - plugin
  - strategies
  - tool connection analyzer/map

## 3. Anthropic dict payload parity

- Updated `AnthropicLlm.partToMessageBlock(...)` so arbitrary `Map` / `List` tool-result payloads are serialized as JSON.
- This avoids Dart `Map.toString()` output leaking into Anthropic tool-result content.

## Validation

- `dart analyze` on changed source and tests: passed
- `dart test` passed:
  - `test/spanner_parity_test.dart`
  - `test/spanner_pubsub_runtime_bootstrap_test.dart`
  - `test/tools_runtime_bootstrap_test.dart`
  - `test/environment_simulation_parity_test.dart`
  - `test/models_parity_batch2_test.dart`

## Notes

- The Python reports also include new integration surfaces such as Slack and IAM connector scaffolding.
- Those were not mirrored in this batch because the corresponding Dart integration modules do not exist yet; adding shallow stubs would not provide functional parity.
- The `response_modalities -> Modality enum` Python fix is not directly applicable because Dart's live config surface stores modalities as strings end-to-end.
