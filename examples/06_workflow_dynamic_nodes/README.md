# Workflow Dynamic Nodes Example (ctx.runNode)

이 예제는 ADK 2.0의 워크플로우 엔진에서 사전에 정의된 정적 엣지(Edge) 구조를 따르지 않고, 실행 중에 조건에 따라 동적으로 노드를 스케줄링하고 대기하는 **동적 노드 실행(Dynamic Node Execution)** 방식을 보여줍니다.

## 주요 개념
- **Dynamic Node Scheduling**: `WorkflowContext.runNode(node, input: ...)`를 사용하면 정적 그래프 정의 외부에서 노드(에이전트 또는 함수)를 런타임에 동적으로 실행할 수 있습니다.
- **Looping & Feedback Patterns**: 워크플로우 실행 중에 루프(`while`)를 사용하여 생성 에이전트와 평가 에이전트를 동적으로 교차 호출하고, 조건이 만족될 때까지 피드백을 전달하며 완성도를 높이는 디자인 패턴(Generator-Evaluator 루프)을 쉽게 설계할 수 있습니다.

## 실행 방법

### 1. API 키 설정
이 예제는 실제 에이전트들을 호출하므로 `GEMINI_API_KEY` 설정이 필요합니다.
```bash
export GEMINI_API_KEY="your-gemini-api-key"
```

### 2. 예제 실행
```bash
dart pub get
dart run bin/main.dart
```
