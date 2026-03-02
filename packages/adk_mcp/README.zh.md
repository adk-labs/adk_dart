# adk_mcp

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | 中文

`adk_mcp` 提供 Dart 版 MCP（Model Context Protocol）客户端基础能力。

## 提供内容

- Streamable HTTP MCP 客户端 (`McpRemoteClient`)
- stdio MCP 客户端 (`McpStdioClient`)
- MCP 常量、方法名、协议版本协商、JSON-RPC 辅助方法

## 平台支持矩阵（当前）

状态说明:

- `✅` 支持
- `⚠️` 部分支持/环境相关
- `❌` 不支持

| 功能/接口 | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | 说明 |
| --- | --- | --- | --- | --- |
| `McpRemoteClient` (Streamable HTTP) | ✅ | ✅ | ✅ | HTTP/HTTPS 传输 |
| 协议协商 + JSON-RPC 辅助方法 | ✅ | ✅ | ✅ | 各平台行为一致 |
| 服务端消息读取 (`readServerMessagesOnce`) | ✅ | ✅ | ✅ | Web 端可能需要 CORS 可用的 MCP 服务端 |
| `McpStdioClient` | ✅ | ⚠️ | ❌ | Web stub 会抛 `UnsupportedError` |
| `StdioConnectionParams` + `Process.start` | ✅ | ⚠️ | ❌ | 依赖本地进程能力/策略 |
| HTTP 会话终止 (`terminateSession`) | ✅ | ✅ | ✅ | 使用 MCP Streamable HTTP DELETE 流程 |
| 内置凭证/令牌生命周期管理器 | ❌ | ❌ | ❌ | 由调用方自行管理 headers/tokens |

## 安装

```bash
dart pub add adk_mcp
```

## 参考

- 详细说明: [README.md](README.md)
- 仓库: <https://github.com/adk-labs/adk_dart>
