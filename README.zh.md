# Agent Development Kit (ADK) for Dart

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | 中文

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![pub package](https://img.shields.io/pub/v/adk_dart.svg)](https://pub.dev/packages/adk_dart)
[![Package Sync](https://github.com/adk-labs/adk_dart/actions/workflows/package-sync.yml/badge.svg)](https://github.com/adk-labs/adk_dart/actions/workflows/package-sync.yml)

ADK Dart 是一个开源的代码优先（Code-First）Dart 框架，用于构建和运行具备模块化运行时原语、工具编排以及 MCP（Model Context Protocol）集成的 AI Agent。

它是 ADK 架构的 Dart 移植版，专注于实用的运行时兼容性与开发者人体工学体验（Developer Ergonomics）。

---

## 最新更新

- **ADK 2.0 工作流与 Managed Agent 支持**：原生支持核心 ADK 2.0 特性：
  - **v2 工作流**：通过 `Workflow`、`BaseNode`、`JoinNode` 等实现声明式节点图调度、依赖管理、条件路由与状态合并。
  - **Managed Agents**：通过 `ManagedAgent` 与 `RemoteMcpServer` 配置映射直接连接 GCP Managed Agents Interactions API。
- **MCP 协议核心包拆分**：新增 `packages/adk_mcp` 并将 Streamable HTTP MCP 传输协议独立为专用包。
- **MCP 规范加固**：增强会话恢复、基于请求 ID 的 SSE 响应匹配、取消通知、具备能力感知的 RPC 调用。
- **兼容性全面扩展**：覆盖会话、工具集、模型/工具集成层的完整运行时兼容性。

## 核心特性

- **代码优先的 Agent 运行时**：使用 `BaseAgent`、`LlmAgent`（`Agent` 别名）及显式调用/会话上下文构建 Agent。
- **事件驱动执行**：通过 `Runner` / `InMemoryRunner` 异步执行 Agent 并流式传输 `Event`。
- **多 Agent 协作**：使用 `subAgents` 构建多层级 Agent 协作与工作流编排。
- **丰富的工具生态**：原生提供 Function 工具、OpenAPI 工具、Google API 工具集、数据工具（BigQuery/Bigtable/Spanner）与 MCP 工具集。
- **MCP 协议集成**：基于 `adk_mcp` 的 `McpToolset` 和 `McpSessionManager`，通过 Streamable HTTP 轻松接入远程 MCP 服务器。
- **开发者 CLI + Web UI**：使用 `adk` CLI（`create`、`run`、`web`、`api_server`）进行脚手架搭建、交互式运行及 Web UI 调试。

## ADK Python 兼容性现状

ADK Dart 旨在表现与 `adk-python` 一致的行为，同时遵循 Dart 原生类型、异步流、包结构及平台约束。当前发布基线追踪 `adk-python` `2.7.0`。

状态图例：

- `✅` 已实现并通过兼容性/运行时测试。
- `⚠️` 已实现，但受平台、凭据或环境约束。
- `🚧` 计划中 / 尚未完全实现。

| `adk-python` 领域 | Dart 状态 | Dart 实现表面 | 说明 |
| --- | --- | --- | --- |
| 包/版本基线 | ✅ | `adkVersion`, 包版本 | `adk_dart`, `adk`, `adk_mcp`, `flutter_adk` 保持对齐；ADK 基线版本为 `2.7.0`。 |
| Agent 与 Runner | ✅ | `BaseAgent`, `LlmAgent`/`Agent`, `SequentialAgent`, `ParallelAgent`, `LoopAgent`, `Runner`, `InMemoryRunner` | 核心调用、实时回退、回溯（Rewind）、会话状态、回调及 Agent Transfer 均已移植。 |
| LLM 流程处理器 | ✅ | `flows/llm_flows` 下的请求/响应处理器 | 涵盖指令、身份、内容、压缩、上下文缓存、代码执行、输出结构模式、工具确认（HITL）及 Agent 转移。 |
| 工作流运行时 | ✅ | `Workflow`, `BaseNode`, 函数/工具/LLM 节点, `NodeTool`, 合并, 路由, 动态节点, 回放 | 重试、超时、输入请求/HITL、并行工作器、回放/重新水化、图序列化及 DOT 可视化均已实现。 |
| 事件与内容转换 | ✅ | `Event`, `EventActions`, 内容/Part 模型, 节点路径构建器 | 包括结构化事件动作、节点路径、函数/工具响应转换与 A2A 元数据保留。 |
| 会话与状态 | ✅ | In-Memory, SQLite, Database, Vertex AI 会话服务, 迁移工具 | 本地及远程会话 API 均已实现。 |
| 内存与制品 | ✅ | In-Memory 内存, Vertex AI 内存/RAG, In-Memory/文件/GCS 制品 | GCS/Vertex 路径依赖 HTTP/Auth 提供者及真实云环境配置。 |
| 工具与工具集 | ✅ | Function 工具, Agent 工具, OpenAPI 工具, Google API 工具, 检索工具, 环境工具, 数据工具 | 内置对 Google Search、URL Context、代码执行、Computer Use、Google Maps、Vertex AI Search 与 Vertex RAG 的支持。 |
| MCP 集成 | ⚠️ | `adk_mcp`, `McpToolset`, `McpSessionManager`, `StreamableHTTPConnectionParams`, `StdioConnectionParams` | Streamable HTTP 在 VM/Flutter/Web 均可用。Stdio 需本地进程执行，仅限 VM。 |
| 模型/供应商 | ✅ | Gemini REST/Live, Anthropic, LiteLLM, Gemma, Apigee, Chat Completions, OpenAI labs | 可插拔传输层，需配置对应 API Key。 |
| 认证与凭据 | ✅ | 认证方案, 凭据管理器, OAuth2 交换/刷新, 服务账号钩子 | 工具认证、OAuth 发现、Token 交换/刷新及会话状态凭据存储均已支持。 |
| 评估与模拟 | ✅ | 评估管理器/服务, 指标评估器, LLM-as-a-judge, 用户模拟器 | 本地/GCS 评估集管理器、多维度指标与模拟器生成均已实现。 |
| 插件与遥测 | ✅ | 插件管理器, 调试/全局/反思/制品保存插件, OpenTelemetry/SQLite | SQLite Trace 持久化、指标度量、自动追踪及生命周期钩子均已就绪。 |
| CLI, 开发服务器, 部署 | ✅ | `adk create/run/web/api_server/deploy/eval/eval_set/conformance/migrate` | 适配 Dart CLI 环境。 |
| A2A 协议 | ✅ | A2A 转换器, 执行器, Agent 卡片, JSON-RPC/REST 任务路由, 远程 A2A Agent | 流式传输、任务恢复/取消/重新订阅、推送配置及 SQLite 持久化队列。 |
| 代码执行器 | ⚠️ | 本地进程, 容器/Docker, GKE, Vertex AI, Cloud Run 沙箱 | 运行时逻辑已完成，依赖外部 Docker/K8s/Vertex/Cloud Run 环境。 |
| 数据/云集成 | ⚠️ | BigQuery, Bigtable, Spanner, Pub/Sub, Secret Manager, Agent Registry, Slack, Toolbox | 运行时客户端与门面均已就绪。 |
| 技能 (Skills) | ✅ | `Skill`, `SkillToolset`, 本地/内存/GCS 技能源, 技能提示词格式化 | 支持内联与目录加载（文件系统加载不支持 Flutter Web）。 |
| Flutter/Web-Safe API | ⚠️ | `adk_core`, `flutter_adk`, Flutter 示例应用 | 暴露 Web-safe API，安全排除 `dart:io` 等 VM 专属依赖。 |

## 我该选用哪个 Package？

| 开发场景 | 推荐 Package | 选用原因 |
| --- | --- | --- |
| 在 Dart VM/CLI 环境下构建 Agent（服务器、命令行工具、测试、完整 API） | `adk_dart` | 提供 ADK Dart 全部运行时能力的基石包 |
| 在 Dart VM/CLI 环境下但希望使用更短的 import 路径 | `adk` | 重新导出 `adk_dart` 的门面包（`package:adk/adk.dart`） |
| 开发 Flutter 跨平台应用（Android/iOS/Web/Linux/macOS/Windows） | `flutter_adk` | 基于 `adk_core` 的 Flutter/Web-safe 包，单 import 即可使用 |

## 安装指南

### 最新稳定版（推荐）

```bash
dart pub add adk_dart
```

若需使用短别名门面包：

```bash
dart pub add adk
```

### 开发版（Git 依赖）

```yaml
dependencies:
  adk_dart:
    git:
      url: https://github.com/adk-labs/adk_dart.git
      ref: main
```

```bash
dart pub get
```

## Gemini API Key 配置

推荐环境变量：

- `GOOGLE_API_KEY`（推荐）
- `GEMINI_API_KEY`（兼容别名）

### 选项 A: Gemini API 模式（默认）

```env
GOOGLE_GENAI_USE_VERTEXAI=0
GOOGLE_API_KEY=your_google_api_key
```

### 选项 B: Vertex AI 模式

```env
GOOGLE_GENAI_USE_VERTEXAI=1
GOOGLE_CLOUD_PROJECT=your-gcp-project-id
GOOGLE_CLOUD_LOCATION=us-central1
GOOGLE_API_KEY=your_google_api_key
```

## Model Context Protocol (MCP)

ADK Dart 全面支持最新的 MCP 规范，并提供独立的底层传输包：

- `packages/adk_mcp`: Dart 版 MCP 传输与生命周期核心库
- `adk_dart` MCP 层: ADK 工具与运行时集成（`McpToolset`, `McpSessionManager` 等）

## 代码示例

### 1. 定义并运行单 Agent

```dart
import 'package:adk_dart/adk_dart.dart';

class EchoModel extends BaseLlm {
  EchoModel() : super(model: 'echo');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String userText = request.contents.isEmpty
        ? ''
        : request.contents.last.parts
              .where((Part part) => part.text != null)
              .map((Part part) => part.text!)
              .join(' ');

    yield LlmResponse(content: Content.modelText('echo: $userText'));
  }
}

Future<void> main() async {
  final Agent agent = Agent(name: 'echo_agent', model: EchoModel());
  final InMemoryRunner runner = InMemoryRunner(agent: agent);

  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'user_1',
    sessionId: 'session_1',
  );

  await for (final Event event in runner.runAsync(
    userId: 'user_1',
    sessionId: session.id,
    newMessage: Content.userText('hello'),
  )) {
    print(event.content?.parts.first.text ?? '');
  }
}
```

### 2. 开发者 CLI 与 Web UI

```bash
dart pub global activate adk_dart
adk create my_agent
cd my_agent
adk run .
adk web --port 8000 .
```

`adk web` 将在 `http://127.0.0.1:8000` 启动本地开发服务与 Web UI。

## 测试

```bash
dart test
dart analyze
```

## 许可证

本项目采用 Apache 2.0 许可证。详见 [LICENSE](LICENSE)。
