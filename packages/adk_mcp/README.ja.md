# adk_mcp

[English](README.md) | [한국어](README.ko.md) | 日本語 | [中文](README.zh.md)

`adk_mcp` は Dart 向け MCP (Model Context Protocol) クライアントプリミティブです。

## 提供機能

- Streamable HTTP MCP client (`McpRemoteClient`)
- stdio MCP client (`McpStdioClient`)
- MCP constants/method names/protocol negotiation/JSON-RPC helpers

## Platform Support Matrix (Current)

Status legend:

- `✅` Supported
- `⚠️` Partial / environment dependent
- `❌` Not supported

| Feature / Surface | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | Notes |
| --- | --- | --- | --- | --- |
| `McpRemoteClient` (Streamable HTTP) | ✅ | ✅ | ✅ | HTTP/HTTPS transport |
| Protocol negotiation + JSON-RPC helpers | ✅ | ✅ | ✅ | Same behavior across platforms |
| Server message loop (`readServerMessagesOnce`) | ✅ | ✅ | ✅ | Web may require CORS-ready MCP server |
| `McpStdioClient` | ✅ | ⚠️ | ❌ | Web stub throws `UnsupportedError` |
| `StdioConnectionParams` + `Process.start` | ✅ | ⚠️ | ❌ | Depends on local process policy |
| HTTP session termination (`terminateSession`) | ✅ | ✅ | ✅ | MCP Streamable HTTP DELETE flow |
| Built-in credential/token lifecycle manager | ❌ | ❌ | ❌ | Caller manages headers/tokens |

## Install

```bash
dart pub add adk_mcp
```

## Links

- Full details: [README.md](README.md)
- Repository: <https://github.com/adk-labs/adk_dart>
