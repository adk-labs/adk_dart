# adk_mcp

[English](README.md) | [한국어](README.ko.md) | 日本語 | [中文](README.zh.md)

`adk_mcp` は Dart 向け MCP (Model Context Protocol) クライアントプリミティブです。

## 提供機能

- Streamable HTTP MCP client (`McpRemoteClient`)
- stdio MCP client (`McpStdioClient`)
- MCP constants/method names/protocol negotiation/JSON-RPC helpers

## Platform Support Matrix (Current)

Status legend:

- `Y` Supported
- `Partial` Partial / environment dependent
- `N` Not supported

| Feature / Surface | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | Notes |
| --- | --- | --- | --- | --- |
| `McpRemoteClient` (Streamable HTTP) | Y | Y | Y | HTTP/HTTPS transport |
| Protocol negotiation + JSON-RPC helpers | Y | Y | Y | Same behavior across platforms |
| Server message loop (`readServerMessagesOnce`) | Y | Y | Y | Web may require CORS-ready MCP server |
| `McpStdioClient` | Y | Partial | N | Web stub throws `UnsupportedError` |
| `StdioConnectionParams` + `Process.start` | Y | Partial | N | Depends on local process policy |
| HTTP session termination (`terminateSession`) | Y | Y | Y | MCP Streamable HTTP DELETE flow |
| Built-in credential/token lifecycle manager | N | N | N | Caller manages headers/tokens |

## Install

```bash
dart pub add adk_mcp
```

## Links

- Full details: [README.md](README.md)
- Repository: <https://github.com/adk-labs/adk_dart>
