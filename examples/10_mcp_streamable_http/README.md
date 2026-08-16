# 10. Streamable HTTP MCP Integration

Demonstrates dynamic Model Context Protocol (MCP) server handshake, tool reflection, and remote RPC execution over Streamable HTTP using `StreamableHTTPConnectionParams` and `McpToolset`.

## Execution

```bash
cd examples/10_mcp_streamable_http
dart pub get
export GEMINI_API_KEY="your-gemini-api-key"
dart run bin/main.dart
```

---

### 한국어
`StreamableHTTPConnectionParams`와 `McpToolset`을 통해 원격 MCP(Model Context Protocol) 엔드포인트와 HTTP 스트리밍 핸드셰이크를 수행하고 동적으로 도구를 디스커버리 및 RPC 호출하는 예제입니다.

### 日本語
`StreamableHTTPConnectionParams` と `McpToolset` を使用して、リモート MCP (Model Context Protocol) エンドポイントとの HTTP ストリーミングハンドシェイクを行い、ツールを動的検出および RPC 呼び出しするサンプルです。

### 中文
使用 `StreamableHTTPConnectionParams` 和 `McpToolset` 与远程 MCP (Model Context Protocol) 端点进行 HTTP 流式握手，并动态发现与 RPC 调用远程工具的示例。
