# Agent Development Kit (ADK) for Dart

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | 中文

ADK Dart 是一个面向 AI Agent 的代码优先 Dart 框架，
提供 Agent 运行时、工具编排和 MCP 集成能力。

## 核心能力

- 代码优先的 Agent 运行时 (`BaseAgent`, `LlmAgent`, `Runner`)
- 基于事件流的执行模型
- 多 Agent 编排 (`Sequential`, `Parallel`, `Loop`)
- Function/OpenAPI/Google API/MCP 工具生态
- `adk` CLI (`create`, `run`, `web`, `api_server`, `deploy`)

## 📦 该选哪个包？

| 你的场景 | 推荐包 | 原因 |
| --- | --- | --- |
| 在 Dart VM/CLI（服务端、工具、测试、完整运行时 API）开发 Agent | `adk_dart` | 主包，提供 ADK Dart 完整运行时能力 |
| 仍在 VM/CLI，但希望更短的 import 路径 | `adk` | `adk_dart` 的 facade 包（`package:adk/adk.dart`） |
| 开发 Flutter 应用（Android/iOS/Web/Linux/macOS/Windows） | `flutter_adk` | 基于 `adk_core` 的 Flutter/Web-safe 接口，单一 import 更易用 |

快速选择规则:

- 默认选 `adk_dart`
- 仅想要短包名且行为保持一致时选 `adk`
- Flutter 应用代码（尤其包含 Web）选 `flutter_adk`

## 平台支持矩阵（当前）

状态说明:

- `✅` 支持
- `⚠️` 部分支持/依赖运行环境
- `❌` 不支持

| 功能/接口 | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | 说明 |
| --- | --- | --- | --- | --- |
| `package:adk_dart/adk_dart.dart` 全量 API | ✅ | ⚠️ | ❌ | 包含 `dart:io`/`dart:ffi`/`dart:mirrors` 路径 |
| `package:adk_dart/adk_core.dart` Web-safe API | ✅ | ✅ | ✅ | 已排除 IO/FFI/mirrors 依赖接口 |
| Agent 运行时 (`Agent`, `Runner`, workflows) | ✅ | ✅ | ✅ | in-memory 路径跨平台可用 |
| MCP Streamable HTTP | ✅ | ✅ | ✅ | Web 端可能需要 MCP 服务端 CORS 配置 |
| MCP stdio (`StdioConnectionParams`) | ✅ | ⚠️ | ❌ | 依赖本地进程能力，Web 不可用 |
| inline Skills (`Skill`, `SkillToolset`) | ✅ | ✅ | ✅ | Web 可用 |
| 目录技能加载 (`loadSkillFromDir`) | ✅ | ⚠️ | ❌ | Web 抛出 `UnsupportedError` |
| CLI (`adk create/run/web/api_server/deploy`) | ✅ | ❌ | ❌ | 仅 VM/终端环境 |
| Dev Web Server + A2A 接口 | ✅ | ❌ | ❌ | 服务端运行时路径 |
| DB/文件后端服务 | ✅ | ⚠️ | ❌ | 受 IO/网络/文件系统能力限制 |

## 安装

```bash
dart pub add adk_dart
```

如果需要更短的 import 包名:

```bash
dart pub add adk
```

## 文档

- 详细功能矩阵/示例: [README.md](README.md)
- 仓库: <https://github.com/adk-labs/adk_dart>
