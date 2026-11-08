---
name: adk-dart-agent-builder
description: >-
  Builds ADK Dart agents and workflows: LlmAgent (Agent) with Gemini, Claude,
  LiteLLM (OpenAI, Ollama, Groq, DeepSeek), or LiteRT-LM; FunctionTool,
  BaseTool, AgentTool, McpToolset, OpenApiToolset, and SkillToolset; ADK 2.0
  Workflow DAG graphs (BaseNode, FunctionNode, AgentNode, JoinNode, routed
  edges, dynamic ctx.runNode, RequestInput HITL pause/resume); multi-agent
  SequentialAgent, ParallelAgent, LoopAgent, and subAgents transfer; session
  state, artifacts, memory, callbacks, plugins, and AgentEvaluator (pass@k,
  pass^k). Use when asked to create or modify an ADK Dart agent, tool, workflow,
  multi-agent pipeline, session/state logic, or evaluation test. Don't use for
  Flutter UI widgets (use flutter-adk-ui-builder) or project/CLI setup (use
  adk-dart-setup).
---

# ADK Dart Agent Builder

Checked against `adk_dart` `2026.11.8` (`adk-python` `2.14.0` baseline).

Read only the reference file that matches the task at hand to keep context lean:

## Reference Guides

| Task | Reference |
| --- | --- |
| First `LlmAgent` (`Agent`), running with `InMemoryRunner`, reading `Stream<Event>`, SSE streaming, multi-LLM models (`Gemini`, `AnthropicLlm`, `LiteLlm`) | [getting-started.md](references/getting-started.md) |
| `FunctionTool`, custom `BaseTool`, confirmation-gated tools (`requireConfirmation`), `AgentTool`, built-in Gemini tools, `McpToolset`, `OpenApiToolset`, `SkillToolset` | [tools-and-mcp.md](references/tools-and-mcp.md) |
| ADK 2.0 `Workflow` DAGs (`BaseNode`, `FunctionNode`, `AgentNode`, `JoinNode`, routed edges, dynamic `ctx.runNode`, HITL `RequestInput`), plus `SequentialAgent`, `ParallelAgent`, `LoopAgent`, `subAgents` | [workflows-and-multi-agent.md](references/workflows-and-multi-agent.md) |
| `Context` / `ToolContext`, session state & `temp:` keys, `SessionService` (`InMemory`, `Sqlite`, `Database`, `VertexAi`), artifacts, memory, callbacks, plugins, and `AgentEvaluator` (`pass@k` / `pass^k`) | [state-sessions-callbacks-eval.md](references/state-sessions-callbacks-eval.md) |
| Common pitfalls ("Rules that bite"), Web/WASM safety (`adk_core.dart` vs `adk_dart.dart`), and unit testing with a fake `BaseLlm` | [best-practices.md](references/best-practices.md) |

---

## Coming from `adk-python` (Quick Translation Table)

| `adk-python` | `adk_dart` (`package:adk_dart/adk_dart.dart` or `package:adk/adk.dart`) |
| --- | --- |
| `Agent(name="...", model="gemini-2.5-flash", instruction="...")` | `Agent(name: '...', model: 'gemini-2.5-flash', instruction: '...')` |
| `FunctionTool(my_fn, require_confirmation=True)` | `FunctionTool(func: myFn, requireConfirmation: true)` |
| `tool_context.state["k"] = v` | `toolContext.state['k'] = v;` |
| `runner.run_async(user_id=..., session_id=..., new_message=...)` | `runner.runAsync(userId: ..., sessionId: ..., newMessage: Content.userText('...'))` (`Stream<Event>`) |
| `event.is_final_response()` | `event.isFinalResponse()` |
| `llm_request.to_generate_content_body()` | `llmRequest.toGenerateContentBody()` |
| `Event(author="agent", text="hello", custom_metadata={...})` | `Event(author: 'agent', text: 'hello', customMetadata: <String, dynamic>{...})` |
| `Workflow(name="wf", edges=[...])` | `Workflow(name: 'wf', edges: <Object>[...])` |
| `JoinNode(name="join")` | `JoinNode(name: 'join')` |
| `McpToolset(connection_params=StreamableHTTPConnectionParams(url=...))` | `McpToolset(connectionParams: StreamableHTTPConnectionParams(url: '...'))` |
| `LiteLlm(model="ollama_chat/gemma2:2b")` | `LiteLlm(model: 'ollama_chat/gemma2:2b', baseUrl: 'http://localhost:11434/v1')` |
