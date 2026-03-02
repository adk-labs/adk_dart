# adk_mcp

[English](README.md) | 한국어 | [日本語](README.ja.md) | [中文](README.zh.md)

`adk_mcp`는 Dart용 MCP(Model Context Protocol) 클라이언트 프리미티브 패키지입니다.

## 포함 기능

- Streamable HTTP MCP 클라이언트 (`McpRemoteClient`)
- stdio MCP 클라이언트 (`McpStdioClient`)
- MCP 상수, 메서드명, 프로토콜 버전 협상, JSON-RPC 헬퍼

## 플랫폼 지원 매트릭스 (현재)

상태 표기:

- `✅` 지원
- `⚠️` 부분 지원/환경 의존
- `❌` 미지원

| 기능/표면 | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | 비고 |
| --- | --- | --- | --- | --- |
| `McpRemoteClient` (Streamable HTTP) | ✅ | ✅ | ✅ | HTTP/HTTPS 전송 |
| 프로토콜 버전 협상 + JSON-RPC 헬퍼 | ✅ | ✅ | ✅ | 전 플랫폼 동일 동작 |
| 서버 메시지 읽기 루프 (`readServerMessagesOnce`) | ✅ | ✅ | ✅ | Web은 CORS 설정된 MCP 서버 필요 |
| `McpStdioClient` | ✅ | ⚠️ | ❌ | Web에서는 stub가 `UnsupportedError` 발생 |
| `StdioConnectionParams` + `Process.start` | ✅ | ⚠️ | ❌ | 로컬 프로세스 실행 정책 영향 |
| HTTP 세션 종료 (`terminateSession`) | ✅ | ✅ | ✅ | MCP Streamable HTTP DELETE 종료 흐름 |
| 내장 토큰/자격증명 수명주기 매니저 | ❌ | ❌ | ❌ | 호출자가 헤더/토큰 직접 관리 |

## 설치

```bash
dart pub add adk_mcp
```

## 참고

- 상세 기능: [README.md](README.md)
- 저장소: <https://github.com/adk-labs/adk_dart>
