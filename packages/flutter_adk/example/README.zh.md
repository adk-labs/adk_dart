# flutter_adk_example

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | 中文

`flutter_adk` 示例应用。

## 多语言 UI 支持

- 支持语言: English / 한국어 / 日本語 / 中文
- 可通过顶部 `Translate` 图标即时切换
- 语言选择会保存到本地存储

## 内置示例

- `Basic Chatbot`: 单 `Agent + FunctionTool`
- `Transfer Multi-Agent`: Coordinator/Dispatcher 模式
- `Workflow Combo`: `SequentialAgent + ParallelAgent + LoopAgent`
- `Sequential` / `Parallel` / `Loop`
- `Agent Team`
- `MCP Toolset`（远程 HTTP）
- `Skills`（inline `Skill + SkillToolset`）

## 平台支持矩阵（当前）

状态说明:

- `Y` 支持
- `Partial` 部分支持/注意事项
- `N` 不支持

| 功能 | Android | iOS | Web | Linux | macOS | Windows | 说明 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 示例 UI/路由/聊天界面 | Y | Y | Y | Y | Y | Y | Flutter 通用 UI 层 |
| Basic/Transfer/Workflow/Team 执行 | Y | Y | Y | Y | Y | Y | 基于 `flutter_adk` `adk_core` 的 in-memory 运行时 |
| MCP Toolset (Streamable HTTP) | Y | Y | Y | Y | Y | Y | Web 可能需要服务端 CORS 配置 |
| Skills (inline) | Y | Y | Y | Y | Y | Y | 不依赖文件系统 |
| 设置持久化 (`shared_preferences`) | Y | Y | Y | Y | Y | Y | Web 使用浏览器存储 |
| 本地进程 MCP stdio 示例 | N | N | N | N | N | N | 本示例仅演示远程 HTTP MCP |
| 目录技能加载示例 | N | N | N | N | N | N | 本示例仅演示 inline skills |

## 运行

```bash
flutter pub get
flutter run
```

Web 构建:

```bash
flutter build web
```

## 使用步骤

1. 在右上角设置中输入并保存 Gemini API Key
2. 使用 MCP 示例时，填写 MCP Streamable HTTP URL（可选 Bearer Token）
3. 通过顶部芯片选择示例
4. 发送消息观察行为

## 注意事项

- 浏览器存储 API Key 存在泄露风险，生产环境建议使用服务端代理
- 仓库包含 `pubspec_overrides.yaml`，用于本地开发时引用最新根源码
