# Workflow Fan-Out / Fan-In Example (JoinNode)

이 예제는 ADK 2.0의 워크플로우 엔진을 사용하여 여러 작업을 병렬로 처리(Fan-Out)하고, 그 결과를 `JoinNode`를 통해 동기화 및 병합(Fan-In)하는 구조를 보여줍니다.

## 주요 개념
- **Workflow**: 노드(Node)와 엣지(Edge)의 방향성 비순환 그래프(DAG) 구조를 조율하고 병렬 실행 및 결과 흐름을 관리합니다.
- **JoinNode**: 지정된 복수의 선행 노드들이 모두 성공적으로 실행 완료될 때까지 대기하고, 완료 시 선행 노드들의 출력 결과를 노드명을 Key로 하는 Map 형태로 병합하여 후속 노드에 전달합니다.

## 실행 방법
1. 의존성 설치:
   ```bash
   dart pub get
   ```
2. 예제 실행:
   ```bash
   dart run bin/main.dart
   ```
