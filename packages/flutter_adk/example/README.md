# flutter_adk_example

English | [한국어](README.ko.md) | [日本語](README.ja.md) | [中文](README.zh.md)

Example app for `flutter_adk`.

## Multilingual UI Support

- Supported UI languages: English, Korean, Japanese, Chinese
- You can switch language from the `Translate (🌐)` icon in the top bar
- Selected language is persisted in local storage

## Included Examples

- `Basic Chatbot`: single `Agent + FunctionTool`
- `Transfer Multi-Agent`: Coordinator/Dispatcher pattern from MAS docs
  - `HelpDeskCoordinator` routes requests to `Billing` and `Support`
- `Workflow Combo`: combined `SequentialAgent + ParallelAgent + LoopAgent`
- `Sequential`: code-write -> review -> refactor flow
- `Parallel`: parallel specialist responses + merge
- `Loop`: Critic/Refiner iterative loop with `exit_loop`
- `Agent Team`: coordinator routing to Greeting/Weather/Farewell team
- `MCP Toolset`: remote MCP with `McpToolset + StreamableHTTPConnectionParams`
- `Skills`: orchestration using inline `Skill + SkillToolset`

## Platform Support Matrix (Current)

Status legend:

- `✅` Supported
- `⚠️` Partial / caveat
- `❌` Not supported

| Feature | Android | iOS | Web | Linux | macOS | Windows | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Example app UI/routing/chat screen | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Flutter shared UI layer |
| Basic/Transfer/Workflow/Team execution | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | In-memory runtime via `flutter_adk` `adk_core` |
| MCP Toolset (Streamable HTTP) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Web may require server CORS setup |
| Skills (inline `Skill` + `SkillToolset`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | No filesystem requirement |
| Settings persistence (`shared_preferences`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Web uses browser storage |
| Local-process MCP stdio example | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | This app demonstrates remote HTTP MCP only |
| Directory skill loading (`loadSkillFromDir`) demo | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | This app demonstrates inline skills only |

## Run

```bash
flutter pub get
flutter run
```

Build for web:

```bash
flutter build web
```

## How to Use

1. Open settings in the top-right and save your Gemini API key
2. For MCP examples, set MCP Streamable HTTP URL (+ optional Bearer token)
3. Choose an example using the top chips
4. Send a message and inspect behavior

Transfer Multi-Agent sample prompts:
- `I was charged twice for my payment`
- `I cannot log in and the app keeps throwing an error`

Workflow Combo sample prompts:
- `Recommend a 2-night 3-day itinerary for Paris`
- `Give UX improvement ideas for a new subscription plan`

Sequential sample prompt:
- `Write a Python function to get the maximum value in a list of numbers`

Parallel sample prompt:
- `Suggest a launch strategy for a new B2B pricing plan`

Loop sample prompt:
- `Write a short fairy tale about a cat going on an adventure`

Agent Team sample prompts:
- `Hi`
- `What time is it in Seoul?`
- `How is the weather in New York?`
- `Thanks, bye`

MCP Toolset sample prompts:
- `Check MCP connection status`
- `List available operations from MCP server tools`

Skills sample prompts:
- `Make this announcement sentence more concise`
- `Organize the new feature rollout plan step by step`

## User Example Builder

- Tap the `New Example` button at the bottom-right to create custom examples
- You can configure multiple agents and choose topology:
  - `Single Agent`
  - `Agent Team`
  - `Sequential Workflow`
  - `Parallel Workflow`
  - `Loop Workflow`
- Created examples are saved locally and reused after app restart

### Graph Connection Rule DSL

Connection conditions support the following DSL:

- `always`
  - Always prioritize this edge
- `intent:<name>`
  - Route when inferred intent is `<name>`
  - Examples: `intent:weather`, `intent:billing`, `intent:login`
- `contains:<keyword>`
  - Route when user message contains `<keyword>` (case-insensitive)
  - Examples: `contains:refund`, `contains:seoul`

Examples:
- `A0 -> A1` condition: `intent:weather`
- `A0 -> A2` condition: `contains:refund`
- `A0 -> A3` condition: `always` (default fallback)

Recommendations:
- For Team topology, define an Entry Agent first and connect routing rules from it
- For Sequential/Parallel/Loop topology, graph connections reflect execution order priorities

## Notes

- Storing API keys in browser storage can expose risks. For production, use a server-side proxy
- `pubspec_overrides.yaml` is included for local dev to use the latest root source
