# flutter_adk

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | 中文

`flutter_adk` 是面向 Flutter 的 ADK Dart 门面包，提供 Web-safe 的核心运行时接口。

## 提供能力

- 重新导出 `package:adk_dart/adk_core.dart`
- Flutter 单一 import：`package:flutter_adk/flutter_adk.dart`
- 包含 `AgentTool`、`UrlContextTool`、Vertex retrieval tools 等最新 Web-safe ADK 接口
- 覆盖 Android/iOS/Web/Linux/macOS/Windows 插件注册

## 什么时候用 `flutter_adk`？

建议选择 `flutter_adk` 的场景:

- 在 Flutter 应用中希望用单一 import 覆盖移动端/桌面端/Web
- 希望默认使用 Web-safe 的 `adk_core` 接口，而不是直接引入 VM 专用 API

建议用其他包的场景:

- 开发 VM/CLI Agent、工具或服务端: `adk_dart`
  （若只想要更短 import 可用 `adk`）

设计意图:

- `flutter_adk` 不是简单改名 wrapper，而是面向 Flutter 的兼容层。
- 它不会直接暴露完整 VM 专用 API，而是优先提供 Web-safe 的 `adk_core`
  运行时接口，以保证 Flutter 多平台行为更一致。

## 包链接

- [flutter_adk](https://pub.dev/packages/flutter_adk): 面向 Flutter
  多平台的 Web-safe ADK 接口包。
- [adk_dart](https://pub.dev/packages/adk_dart): 提供 ADK Dart VM/CLI
  全量运行时 API 的核心包。
- [adk](https://pub.dev/packages/adk): 以短包名重新导出 `adk_dart` 的 facade 包。

## ADK 2.0 兼容性

本包与 ADK 2.0 保持一致，支持 v2 工作流（声明式节点图调度、条件路由和状态合并）与 GCP Managed Agent 整合（包括 `ManagedAgent` 和 `RemoteMcpServer` 配置映射）以实现混合设备端 + 云端执行。

## 平台支持矩阵（当前）

状态说明:

- `Y` 支持
- `Partial` 支持但有注意事项
- `N` 不支持

| 功能 | Android | iOS | Web | Linux | macOS | Windows | 说明 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 单一 import (`package:flutter_adk/flutter_adk.dart`) | Y | Y | Y | Y | Y | Y | 重新导出 web-safe `adk_core` |
| Agent 运行时 (`Agent`, `Runner`, workflows) | Y | Y | Y | Y | Y | Y | in-memory 路径跨平台 |
| `Gemini` 模型调用 | Y | Y | Partial | Y | Y | Y | Web 端需关注 BYOK/CORS/密钥安全 |
| Built-in model tools (`UrlContextTool`, Vertex retrieval) | Y | Y | Y | Y | Y | Y | 由 Gemini/Vertex backend 执行 tool |
| MCP Toolset (Streamable HTTP) | Y | Y | Y | Y | Y | Y | 连接远程 MCP HTTP 服务 |
| MCP Toolset (stdio) | Partial | Partial | N | Y | Y | Y | Web 无法拉起本地进程 |
| Skills (inline) | Y | Y | Y | Y | Y | Y | inline skill 跨平台可用 |
| 目录技能加载 (`loadSkillFromDir`) | Y | Y | N | Y | Y | Y | Web 抛 `UnsupportedError` |
| 插件 helper (`getPlatformVersion`) | Y | Y | Y | Y | Y | Y | 平台通道/浏览器 user-agent |
| VM/CLI 能力 (`adk`/dev server/deploy) | N | N | N | N | N | N | 不在 Flutter 包范围内 |

## 安装

```bash
flutter pub add flutter_adk
```

或在 `pubspec.yaml` 中配置：

```yaml
dependencies:
  flutter_adk: ^2026.8.17+3
```

## 快速上手 (开箱即用的聊天 UI)

只需几行代码即可在 Flutter 应用中直接嵌入 AI 智能体对话界面：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final agent = LlmAgent(
      name: 'assistant',
      model: 'gemini-2.5-flash',
      instruction: '你是一个乐于助人且友好的 Flutter 助手。',
    );

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('ADK Flutter 聊天')),
        body: AdkChatView(
          agent: agent,
          inputPlaceholder: '请输入问题...',
        ),
      ),
    );
  }
}
```

## 参考

- 完整说明: [README.md](README.md)
- 深入矩阵说明: `knowledge/2026-03-01_18-20-00_flutter_adk_platform_support_matrix.md`
