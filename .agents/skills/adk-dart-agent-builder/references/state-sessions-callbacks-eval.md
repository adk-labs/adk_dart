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
- **`SqliteSessionService('sessions.db', cascadeDelete: true)`**: Local SQLite persistence via FFI (VM-only; positional `dbPath`).
- **`DatabaseSessionService('postgresql://user:pass@localhost:5432/adk')`**: PostgreSQL / MySQL / SQLite persistence (VM-only; positional `dbUrl`).
- **`MongoDbSessionService(dbUrl: 'mongodb://localhost:27017', databaseName: 'adk_sessions')`**: MongoDB session persistence.
- **`VertexAiSessionService(...)`**: Managed Google Cloud Vertex AI session persistence.
- **`AdkStorageSessionService.custom(...)`** (`package:flutter_adk`): 2-line adapter for `SharedPreferences`, `FlutterSecureStorage`, or Hive on Flutter.

### `App`, Event Compaction & Resumability
Wrap a root agent in `App` to configure context compaction (`EventsCompactionConfig`) and invocation resumability (`ResumabilityConfig`):
```dart
final App app = App(
  name: 'support_app',
  rootAgent: rootAgent,
  resumabilityConfig: ResumabilityConfig(isResumable: true),
  eventsCompactionConfig: EventsCompactionConfig(
    compactionInterval: 10,
    overlapSize: 2,
    // Rule: tokenThreshold and eventRetentionSize MUST be set together if used:
    tokenThreshold: 64000,
    eventRetentionSize: 10,
  ),
);
```

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

// 1. Run an evaluation dataset file or directory against an agent:
await AgentEvaluator.evaluate(
  rootAgent: myAgent,
  evalDatasetFilePathOrDir: 'test/evals/weather_agent.test.json',
  repeatNum: 3,
  parallelism: 4,
);

// 2. Multi-run evaluation aggregation (pass@k and pass^k):
// - pass_at_k (pass@k): Combinatorial probability of >=1 success in k samples.
// - pass_hat_k (pass^k): Combinatorial probability of all k samples succeeding.
final List<MultiRunCaseResult> multiRunResults =
    EvalCaseResultMultiRunAggregator.aggregate(
  evalCaseResultsAcrossRuns,
  multiRunConfig: MultiRunConfig(
    numRuns: 5,
    crossRunCriteria: <MultiRunCriterion>[
      PassKMultiRunCriterion(method: 'pass_at_k', k: 3, threshold: 0.8),
      PassKMultiRunCriterion(method: 'pass_hat_k', k: 3, threshold: 0.5),
    ],
  ),
);
```
