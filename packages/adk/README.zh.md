# Agent Development Kit (ADK) for Dart (`adk`)

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | 中文

`adk` 是 `adk_dart` 的短包名门面（facade）包。

## 包定位

- 短 import：`package:adk/adk.dart`
- 重新导出 `adk_dart` API
- 提供 `adk` CLI 入口

## 什么时候用 `adk`？

建议选择 `adk` 的场景:

- 在 Dart VM/CLI 环境中希望使用更短 import（`package:adk/adk.dart`）
- 希望保持与 `adk_dart` 完全一致的行为，只是包名更简洁

建议用其他包的场景:

- Flutter 应用代码（尤其包含 Web）: `flutter_adk`
- 希望显式使用核心包名: `adk_dart`

设计意图:

- `adk` 的定位是命名/易用性 facade，而不是运行时分叉。
- 也就是说，当你想用更短 import，同时保持与 `adk_dart` 一致的 VM
  优先运行时行为时，选择 `adk`。

## 平台支持矩阵（当前）

状态说明:

- `Y` 支持
- `Partial` 部分支持/环境相关
- `N` 不支持

| 功能/接口 | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | 说明 |
| --- | --- | --- | --- | --- |
| `package:adk/adk.dart` facade import | Y | Partial | N | 重新导出 `adk_dart` 全量接口 |
| `adk` CLI 可执行入口 | Y | N | N | 仅 VM/终端环境 |
| 经 facade 使用运行时/工具能力 | Y | Partial | N | 约束与 `adk_dart` 保持一致 |
| 本包是否提供 web-safe 专用入口 | N | N | N | 请使用 `adk_dart/adk_core.dart` 或 `flutter_adk` |

## 安装

```bash
dart pub add adk
```

## 参考

- 详细说明: [README.md](README.md)
- 核心包: <https://pub.dev/packages/adk_dart>
