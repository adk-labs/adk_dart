# 13. Agent-to-Agent (A2A) Standard Protocol

Demonstrates full compliance with the open Agent-to-Agent (A2A) protocol: auto-generating discovery `AgentCard` metadata, wrapping executors via `toA2a`, and managing asynchronous event queues via `A2aEventQueue`.

## Execution

```bash
cd examples/13_a2a_agent_protocol
dart pub get
dart run bin/main.dart
```

---

### 한국어
오픈 Agent-to-Agent (A2A) 표준 프로토콜 사양에 따라 `AgentCard` 디스커버리 메타데이터를 발행하고, `A2aAgentExecutor` 및 `A2aEventQueue`를 통해 다중 에이전트 간 RPC 태스크 수명주기를 관리하는 예제입니다.

### 日本語
オープン Agent-to-Agent (A2A) 標準プロトコル仕様に準拠し、`AgentCard` ディスカバリメタデータを公開し、`A2aAgentExecutor` と `A2aEventQueue` を介してマルチエージェント間の RPC タスクライフサイクルを管理するサンプルです。

### 中文
遵循开放 Agent-to-Agent (A2A) 标准协议规范，发布 `AgentCard` 服务发现元数据，并通过 `A2aAgentExecutor` 与 `A2aEventQueue` 管理多智能体间 RPC 任务生命周期的示例。
