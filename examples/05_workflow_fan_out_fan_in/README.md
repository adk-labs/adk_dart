# 05. Workflow Fan-Out / Fan-In

Demonstrates ADK 2.0 Directed Acyclic Graph (DAG) workflows featuring parallel branch scheduling (`Fan-Out`) and deterministic synchronization barriers (`Fan-In`).

## Execution

```bash
cd examples/05_workflow_fan_out_fan_in
dart pub get
export GEMINI_API_KEY="your-gemini-api-key"
dart run bin/main.dart
```

---

### 한국어
ADK 2.0 유향 비순환 그래프(DAG) 워크플로우를 구성하여 다중 추론 노드의 비동기 동시 실행(`Fan-Out`) 및 결과 합류 동기화 배리어(`Fan-In`)를 구현하는 오케스트레이션 예제입니다.

### 日本語
ADK 2.0 有向非巡回グラフ (DAG) ワークフローを構築し、複数推論ノードの非同期並行実行 (`Fan-Out`) および結果集約同期バリア (`Fan-In`) を実装するオーケストレーションサンプルです。

### 中文
构建 ADK 2.0 有向无环图 (DAG) 工作流，实现多推理节点的异步并发执行 (`Fan-Out`) 与结果聚合同步屏障 (`Fan-In`) 的编排示例。
