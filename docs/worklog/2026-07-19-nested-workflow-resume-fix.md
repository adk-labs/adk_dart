# 2026-07-19 Nested Workflow Resume and Load Artifacts Parity Sync

## Overview
This worklog documents the investigation and resolution of the failing nested workflow resume test (`workflow runtime parity resumes nested workflow with request input`), as well as alignment with the upstream `adk-python` load_artifacts_tool inline MIME type blocklist behavior.

## Changes Implemented

### 1. AgentNode.run finalEvent Filtering
- **File**: `lib/src/workflow/workflow.dart`
- **Issue**: During a nested workflow execution, the inner workflow emits `agentState` (checkpoint) and `endOfAgent` events. The existing `AgentNode.run` event loop was catching these as `isFinalResponse() == true` and assigning them to `finalEvent`. Because these checkpoint events contain no content output, `_outputFromAgentEvent(finalEvent)` returned `null`, causing the parent scheduler to misclassify the completed nested workflow node as still `waiting`.
- **Resolution**: Added checks to ignore events containing `endOfAgent` or `agentState` when matching the `finalEvent` of an `AgentNode` execution.

### 2. Yield Resolved Outputs of Resumed Nodes
- **File**: `lib/src/workflow/workflow.dart`
- **Issue**: When resuming a workflow containing a request-input node with `rerunOnResume: false` (such as `inner_task` inside the nested workflow parity test), its output is reconstructed via `previousResult` and loaded into the `outputs` map during rehydration. However, the outputs loop in `runAsyncImpl` was checking `isRequestInputNode` against history events and skipping this node because it had originally yielded a `RequestInput` function call.
- **Resolution**: Removed the obsolete `isRequestInputNode` check in `runAsyncImpl`. Nodes that yielded `RequestInput` in a *previous* session (and are now completed in the current resume run) are no longer skipped. Nodes that yielded `RequestInput` in the *current* run are still skipped via `workflowContext.requestInputNodeKeys.contains(entry.key)`.

### 3. Load Artifacts Tool unsupported inline MIME Subtypes Blocklist
- **File**: `lib/src/tools/load_artifacts_tool.dart`
- **Issue**: Gemini API does not support SVG/XML image variants as inline image data (yielding 400 Bad Request).
- **Resolution**: Added `_geminiUnsupportedInlineSubtypes` containing `image/svg`, `image/svg+xml`, and `image/xml`. Enhanced `_isInlineMimeTypeSupported` to block these subtypes so they fall through to the text-decoding path and are delivered to the model as text, matching Python's `_as_safe_part_for_llm` behavior.

### 4. Build and Update Bundled adk-web Assets
- **Web App Directory**: `ref/adk-web`
- **Output Directory**: `adk-dart/adk_dart/lib/src/cli/browser`
- **Resolution**:
  - Rebuilt the latest `adk-web` Angular application using `npm run build`.
  - Copied the compiled JS chunks, index.html, styles, and SVG resources into `lib/src/cli/browser` in `adk-dart` to update the bundled Web UI with the latest features (e.g. dot-nested navigation breadcrumbs, bidi streaming restarts, and usage metadata tracking).

## Verification
- Ran all 1,483 unit and integration tests (`dart test`), including `test/dev_web_server_test.dart`.
- All tests passed successfully with 0 failures, verifying both runtime parity and web server serving correctness.
