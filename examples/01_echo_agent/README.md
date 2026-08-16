# 01. Echo Agent

Demonstrates initializing and executing an agent pipeline with a custom `BaseLlm` engine implementation, lifecycle hooks, and `InMemoryRunner` orchestration.

## Execution

```bash
cd examples/01_echo_agent
dart pub get
dart run bin/main.dart
```

---

### 한국어
커스텀 `BaseLlm` 추론 엔진(`EchoModel`) 서브클래싱, `Runner` 인보케이션 수명주기, 그리고 `Session` 상태 전파를 실증하는 기초 아키텍처 예제입니다.

### 日本語
カスタム `BaseLlm` 推論エンジン (`EchoModel`) のサブクラス化、`Runner` 呼び出しライフサイクル、および `Session` 状態伝播を実証する基本アーキテクチャサンプルです。

### 中文
演示自定义 `BaseLlm` 推理引擎 (`EchoModel`) 子类化、`Runner` 调用生命周期以及 `Session` 状态传播的基础架构示例。
