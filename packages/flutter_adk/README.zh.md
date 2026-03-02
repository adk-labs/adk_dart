# flutter_adk

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | 中文

`flutter_adk` 是面向 Flutter 的 ADK Dart 门面包，提供 Web-safe 的核心运行时接口。

## 提供能力

- 重新导出 `package:adk_dart/adk_core.dart`
- Flutter 单一 import：`package:flutter_adk/flutter_adk.dart`
- 覆盖 Android/iOS/Web/Linux/macOS/Windows 插件注册

## ✅ 什么时候用 `flutter_adk`？

建议选择 `flutter_adk` 的场景:

- 在 Flutter 应用中希望用单一 import 覆盖移动端/桌面端/Web
- 希望默认使用 Web-safe 的 `adk_core` 接口，而不是直接引入 VM 专用 API

建议用其他包的场景:

- 开发 VM/CLI Agent、工具或服务端: `adk_dart`
  （若只想要更短 import 可用 `adk`）

## 平台支持矩阵（当前）

状态说明:

- `✅` 支持
- `⚠️` 支持但有注意事项
- `❌` 不支持

| 功能 | Android | iOS | Web | Linux | macOS | Windows | 说明 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 单一 import (`package:flutter_adk/flutter_adk.dart`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 重新导出 web-safe `adk_core` |
| Agent 运行时 (`Agent`, `Runner`, workflows) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | in-memory 路径跨平台 |
| `Gemini` 模型调用 | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ | Web 端需关注 BYOK/CORS/密钥安全 |
| MCP Toolset (Streamable HTTP) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 连接远程 MCP HTTP 服务 |
| MCP Toolset (stdio) | ⚠️ | ⚠️ | ❌ | ✅ | ✅ | ✅ | Web 无法拉起本地进程 |
| Skills (inline) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | inline skill 跨平台可用 |
| 目录技能加载 (`loadSkillFromDir`) | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | Web 抛 `UnsupportedError` |
| 插件 helper (`getPlatformVersion`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 平台通道/浏览器 user-agent |
| VM/CLI 能力 (`adk`/dev server/deploy) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 不在 Flutter 包范围内 |

## 使用

```dart
import 'package:flutter_adk/flutter_adk.dart';
```

## 参考

- 完整说明: [README.md](README.md)
- 深入矩阵说明: `knowledge/2026-03-01_18-20-00_flutter_adk_platform_support_matrix.md`
