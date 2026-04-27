# 2026-04-27 Latest Reference Sync

Reference baselines:

- `adk-python`: `e967f281..c87ee1ee`
- `adk-js`: `f6bfead..220d75b`
- `adk-java`: `26429af3..52323b44`

## Work Units

### 1. Web Page Fetch Security

- Work: Hardened `loadWebPage` to reject non-HTTP(S) URLs, localhost, loopback, private, link-local, multicast, and other restricted IP targets by default. Added an explicit `allowPrivateAddresses` test-only escape hatch.
- Reason: The latest Python changes tightened `load_web_page` behavior to reduce SSRF and local-file access risk. Dart needed equivalent default-safe behavior.

### 2. Schema Dereferencing Safety

- Work: Added circular `$ref` detection in Gemini schema dereferencing and replaced cycles with an object placeholder that describes the circular reference.
- Reason: Recursive JSON schema definitions can otherwise loop indefinitely while building Gemini tool declarations.

### 3. Model Adapter Parity

- Work: Added Anthropic thinking block request/response support, including signed thinking parts and streaming `thinking_delta`/`signature_delta` aggregation.
- Work: Added Anthropic thinking budget translation from `thinkingConfig`.
- Work: Fixed LiteLLM/OpenAI audio inline-data conversion to emit `input_audio` instead of image data URLs, and represented OpenAI/Azure audio file references as text references.
- Work: Extracted Google API version suffixes from Google `baseUrl` values such as `/v1alpha` before REST/interactions/live calls.
- Reason: Recent Python and JS changes improved provider-specific request fidelity and thought/signature preservation.

### 4. Context Cache and Usage Metadata

- Work: Enforced Gemini's minimum cache token threshold of 4096 tokens when recreating context caches.
- Work: Preserved matching prefix fingerprint metadata when cache recreation fails.
- Work: Preserved LLM usage metadata on `LlmEventSummarizer` compaction events.
- Reason: Cache metadata must remain stable across failed recreations, and compaction LLM token usage should remain observable.

### 5. Memory and Analytics Scope

- Work: Encoded Vertex RAG memory source display names with a versioned base64url format and retained legacy parsing for old records.
- Work: Added BigQuery analytics capture for LLM cache metadata in response content and event attributes.
- Reason: Plain `app.user.session` names break when identifiers contain dots, and cache metadata is needed for analytics parity.

### 6. Tool Runtime Parity

- Work: Added `run_skill_inline_script` to `SkillToolset`.
- Work: Added `excludedPredefinedFunctions` handling for `ComputerUseToolset`.
- Work: Added bracket JSONPath support for streaming function-call partial arguments.
- Work: Made parallel function-call execution fail eagerly and deep-merge nested state deltas.
- Reason: JS/Python references added script execution, computer-use filtering, stronger streaming argument reconstruction, and safer parallel function-call semantics.

## Verification

- Passed: `dart analyze` on changed implementation and test files.
- Passed: targeted parity tests:
  - `test/load_web_page_test.dart`
  - `test/tools_batch2_parity_test.dart`
  - `test/vertex_memory_services_parity_test.dart`
  - `test/models_parity_batch2_test.dart`
  - `test/anthropic_runtime_parity_test.dart`
  - `test/google_llm_rest_test.dart`
  - `test/compaction_parity_test.dart`
  - `test/computer_use_parity_test.dart`
  - `test/utils_missing_parity_test.dart`
  - `test/skill_toolset_parity_test.dart`
- Full `dart test` still has existing `test/dev_web_server_test.dart` failures unrelated to this sync:
  - `loads extra plugin via dynamic file-path class spec`
  - `retries and drains persisted a2a push deliveries after server restart`
