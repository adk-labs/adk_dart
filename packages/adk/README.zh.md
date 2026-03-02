# Agent Development Kit (ADK) for Dart (`adk`)

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | 中文

`adk` 是 `adk_dart` 的短包名门面（facade）包。

## 包定位

- 短 import：`package:adk/adk.dart`
- 重新导出 `adk_dart` API
- 提供 `adk` CLI 入口

## 平台支持矩阵（当前）

状态说明:

- `✅` 支持
- `⚠️` 部分支持/环境相关
- `❌` 不支持

| 功能/接口 | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | 说明 |
| --- | --- | --- | --- | --- |
| `package:adk/adk.dart` facade import | ✅ | ⚠️ | ❌ | 重新导出 `adk_dart` 全量接口 |
| `adk` CLI 可执行入口 | ✅ | ❌ | ❌ | 仅 VM/终端环境 |
| 经 facade 使用运行时/工具能力 | ✅ | ⚠️ | ❌ | 约束与 `adk_dart` 保持一致 |
| 本包是否提供 web-safe 专用入口 | ❌ | ❌ | ❌ | 请使用 `adk_dart/adk_core.dart` 或 `flutter_adk` |

## 安装

```bash
dart pub add adk
```

## 参考

- 详细说明: [README.md](README.md)
- 核心包: <https://pub.dev/packages/adk_dart>
