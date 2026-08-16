# 06. Workflow Dynamic Nodes

Demonstrates dynamic graph node injection, runtime topological graph mutation, and contextual state propagation during workflow execution.

## Execution

```bash
cd examples/06_workflow_dynamic_nodes
dart pub get
export GEMINI_API_KEY="your-gemini-api-key"
dart run bin/main.dart
```

---

### 한국어
워크플로우 실행 중 선행 노드의 추론 결과 및 조건에 따라 위상 그래프를 런타임에 동적으로 변이(Mutation)시키고 추가 노드를 스케줄링하는 고급 워크플로우 예제입니다.

### 日本語
ワークフロー実行中に、先行ノードの推論結果や条件に応じてトポロジカルグラフを実行時に動的変異 (Mutation) させ、追加ノードをスケジュールする高度なワークフローサンプルです。

### 中文
在工作流执行过程中根据前置节点的推理结果与条件，在运行时动态变异 (Mutation) 拓扑图并调度额外节点的高级工作流示例。
