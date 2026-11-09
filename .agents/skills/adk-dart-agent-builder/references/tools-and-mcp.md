# Tools, Toolsets & MCP in ADK Dart

## 1. `FunctionTool` (Dart Functions as Tools)

On Dart VM, `FunctionTool` can wrap any Dart function and automatically infer parameter names, types, enums, and optional parameters:

```dart
import 'package:adk_dart/adk_dart.dart';

enum TemperatureUnit { celsius, fahrenheit }

Map<String, Object?> getWeather(
  String city, {
  TemperatureUnit unit = TemperatureUnit.celsius,
  ToolContext? toolContext,
}) {
  toolContext?.state['last_queried_city'] = city;
  return <String, Object?>{
    'city': city,
    'temperature': unit == TemperatureUnit.celsius ? 22 : 72,
    'unit': unit.name,
  };
}

final FunctionTool weatherTool = FunctionTool(
  func: getWeather,
  name: 'get_weather',
  description: 'Gets the current weather for a city.',
);
```

- **`ToolContext` Injection**: A parameter named `toolContext` (or typed `ToolContext`) is automatically injected by the runtime and excluded from the LLM schema.
- **Tool Display Names**: MCP tools with `title` (or custom tools populating `customMetadata`) expose display titles in `event.customMetadata['adk:tool_display_names']` (`toolDisplayNamesMetadataKey`).
- **Return Values**: Return JSON-serializable values (`Map<String, Object?>`, `List`, `String`, `num`, `bool`, `null`).

---

## 2. Custom `BaseTool` (Recommended for Flutter Web / WASM & Explicit Schemas)

Because Flutter Web and AOT do not support `dart:mirrors`, subclass `BaseTool` (or provide an explicit declaration) when targeting `adk_core.dart` / `flutter_adk`:

```dart
class StockPriceTool extends BaseTool {
  StockPriceTool()
      : super(
          name: 'get_stock_price',
          description: 'Fetches the current stock price for a ticker symbol.',
        );

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, Object?>{
        'type': 'OBJECT',
        'properties': <String, Object?>{
          'ticker': <String, Object?>{
            'type': 'STRING',
            'description': 'Ticker symbol such as GOOG.',
          },
        },
        'required': <String>['ticker'],
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final String ticker = (args['ticker'] as String? ?? '').toUpperCase();
    return <String, Object?>{'ticker': ticker, 'price': 185.42};
  }
}
```

---

## 3. Confirmation-Gated Tools (Human-in-the-Loop)

Set `requireConfirmation: true` on `FunctionTool` (or call `toolContext.requestConfirmation(...)` inside `run`):

```dart
final FunctionTool transferFundsTool = FunctionTool(
  func: ({required String toAccount, required double amount}) {
    return <String, Object?>{'status': 'transferred', 'amount': amount};
  },
  name: 'transfer_funds',
  description: 'Transfers money to an external account.',
  requireConfirmation: true,
);
```

When the model calls `transfer_funds`, the runtime pauses execution before invoking the function and emits a `FunctionCall` named `adk_request_confirmation`. Resume by sending a `FunctionResponse` with the synthetic call's `id` and `{'confirmed': true}` (or `false`).

---

## 4. `AgentTool` (Agent-as-a-Tool)

Wrap a specialist `BaseAgent` inside `AgentTool` so a parent agent can invoke it like a function call and receive its response without transferring conversation ownership:

```dart
final AgentTool mathSpecialistTool = AgentTool(
  agent: mathAgent,
  skipSummarization: false,
);
```

---

## 5. Model Context Protocol (`McpToolset`)

Connect to remote Streamable HTTP MCP servers (works on VM, Mobile, Desktop, and Web) or local Stdio MCP servers (VM-only):

```dart
// Streamable HTTP (Cross-Platform)
final McpToolset remoteMcp = McpToolset(
  connectionParams: StreamableHTTPConnectionParams(
    url: 'http://localhost:3000/mcp',
    headers: <String, String>{'Authorization': 'Bearer token'},
  ),
  toolFilter: <String>['search_docs', 'fetch_page'],
);

// Stdio Subprocess (Dart VM / Desktop only)
final McpToolset stdioMcp = McpToolset(
  connectionParams: StdioConnectionParams(
    command: 'npx',
    arguments: <String>['-y', '@modelcontextprotocol/server-filesystem', '/tmp'],
  ),
);
```

Always call `await runner.close()` (or `await remoteMcp.close()`) when finished to cleanly close MCP sessions.

---

## 6. `OpenAPIToolset`, `SkillToolset`, `ToolSearchToolset`, `ModelConsultTool`, and Built-in Gemini Tools

- **`OpenAPIToolset`**: Parses OpenAPI 3.x YAML/JSON specs (including local/relative/remote multi-document `$ref` via `externalDocuments`) into callable `RestApiTool` instances:
  ```dart
  final OpenAPIToolset petStore = OpenAPIToolset(
    specStr: openApiJsonString,
    specStrType: 'json',
  );
  ```
- **`SkillToolset`**: Exposes inline `Skill` definitions or directory-loaded skills (`loadSkillFromDir`) via `list_skills`, `load_skill`, `load_skill_resource`, and `run_skill_script`:
  ```dart
  final SkillToolset skills = SkillToolset(
    skills: <Skill>[loadSkillFromDir('.agents/skills/adk-dart-agent-builder')],
    discoveryMode: SkillDiscoveryMode.lazy,
    lifecycleConfig: SkillLifecycleConfig(enabled: true),
  );
  ```
- **`ToolSearchToolset`**: Defers large tool catalogs behind a search tool (`tool_search`) so only relevant tools are loaded into the active prompt window:
  ```dart
  final ToolSearchToolset deferredTools = ToolSearchToolset(
    tools: <Object>[weatherTool, StockPriceTool()],
    config: const ToolSearchConfig(maxResults: 5),
  );
  ```
- **`ModelConsultTool` & `ForceEscalationPlugin`**: Lets an agent consult a stronger advisor model (`consult_model`) mid-turn, optionally enforced by `ForceEscalationPlugin(forceFirstConsult: true, forceOnRepeat: 3, requireConsultBefore: <String>{'deploy'})`.
- **Built-in Gemini Tools**: `GoogleSearchTool(bypassMultiToolsLimit: true)`, `UrlContextTool()`, `VertexAiSearchTool(...)`, `VertexRagRetrievalTool(...)`, and `BuiltInCodeExecutor()`.
