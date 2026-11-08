# State, Sessions, Callbacks, Plugins & Evaluation

## 1. Session State & Key Prefixes

Read and write state through `ToolContext` / `CallbackContext` (`context.state['key'] = value`) or `outputKey` on `LlmAgent`:

| Prefix | Scope & Persistence |
| --- | --- |
| `(none)` | Session-scoped (`session.state['topic']`). Persisted for the session's lifetime. |
| `user:` | User-scoped (`session.state['user:theme']`). Shared across all sessions of the same `userId` in persistent session services. |
| `app:` | App-scoped (`session.state['app:config']`). Shared across all users of the `appName`. |
| `temp:` | Invocation-scoped (`session.state['temp:scratch']`). Visible to later steps in the same `runAsync` invocation (and forwarded to `AgentTool` child runs), then stripped before storage persistence. |

---

## 2. Session, Artifact & Memory Services

### Session Services
- **`InMemorySessionService()`**: Default zero-config in-memory store (Web-safe).
- **`SqliteSessionService(dbPath: 'sessions.db')`**: Local SQLite persistence via FFI (VM-only).
- **`DatabaseSessionService(dbUrl: 'postgresql://...')`**: PostgreSQL / MySQL / SQLite persistence (VM-only).
- **`MongoDbSessionService(...)`**: MongoDB session persistence.
- **`VertexAiSessionService(...)`**: Managed Google Cloud Vertex AI session persistence.
- **`AdkStorageSessionService.custom(...)`** (`package:flutter_adk`): 2-line adapter for `SharedPreferences`, `FlutterSecureStorage`, or Hive on Flutter.

### Artifact & Memory Services
- **Artifacts**: `InMemoryArtifactService()`, `FileArtifactService(rootDir: ...)` (preserves exact line endings), `GcsArtifactService(bucketName: ...)`. Save/load inside tools or callbacks via `await context.saveArtifact(filename, part)` and `await context.loadArtifact(filename)`.
- **Memory**: `InMemoryMemoryService()`, `SqliteMemoryService(...)` (with Latin & CJK bigram indexing), `MongoDbMemoryService(...)`, `VertexAiMemoryBankService(...)`, `VertexAiRagMemoryService(...)`.

---

## 3. Agent Callbacks & App Plugins

### Six Agent Callbacks on `LlmAgent`
- `beforeAgentCallback` / `afterAgentCallback`
- `beforeModelCallback` / `afterModelCallback`
- `beforeToolCallback` / `afterToolCallback`

Returning a non-null `Content` (from agent callbacks), `LlmResponse` (from model callbacks), or `Map<String, dynamic>` (from tool callbacks) short-circuits the underlying execution and uses that return value instead. Returning `null` proceeds normally.

### Built-in Plugins (`Runner(plugins: [...])`)
- **`ReflectAndRetryToolPlugin(maxRetries: 3)`**: Intercepts tool execution errors and prompts the model to self-correct arguments.
- **`ReflectAndRetryModelPlugin(maxRetries: 2)`**: Recovers from `MALFORMED_FUNCTION_CALL` and reserved tool call errors.
- **`SaveFilesAsArtifactsPlugin()`**: Automatically persists uploaded/generated files as session artifacts.
- **`LoggingPlugin()` / `DebugLoggingPlugin()`**: Logs lifecycle events and model/tool payloads.
- **`BigQueryAgentAnalyticsPlugin(...)`**: Streams structured invocation, tool, and workflow node observation telemetry to BigQuery.

---

## 4. Evaluation (`AgentEvaluator` & Multi-Run `pass@k` / `pass^k`)

Evaluate agent trajectories and final responses programmatically or via `adk eval`:

```dart
import 'package:adk_dart/evaluation.dart';

// Multi-run evaluation aggregation (pass@k and pass^k):
// - pass@k: Fraction of cases with at least 1 passing run across k runs.
// - pass^k: Fraction of cases where all k runs passed.
final EvalCaseResultMultiRunAggregator aggregator =
    EvalCaseResultMultiRunAggregator();
final List<MultiRunCaseResult> multiRunResults =
    aggregator.aggregate(caseResultsAcrossRuns);
```
