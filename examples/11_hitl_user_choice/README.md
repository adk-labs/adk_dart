# 11. Human-In-The-Loop (Interactive Choice Interceptor)

Demonstrates deterministic Human-In-The-Loop (HITL) runtime interception where the agent emits structured choice options via `GetUserChoiceTool`, suspends execution, and resumes seamlessly upon user input.

## Execution

```bash
cd examples/11_hitl_user_choice
dart pub get
export GEMINI_API_KEY="your-gemini-api-key"
dart run bin/main.dart
```

---

### 한국어
`GetUserChoiceTool`을 활용하여 에이전트 추론 루프를 일시 중단(Suspension)하고, 구조화된 사용자 선택지 인터럽트를 처리한 후 컨텍스트를 안전하게 재개(Resumption)하는 HITL 예제입니다.

### 日本語
`GetUserChoiceTool` を使用してエージェント推論ループを一時中断 (Suspension) し、構造化されたユーザー選択肢割り込みを処理してコンテキストを安全に再開 (Resumption) する HITL サンプルです。

### 中文
利用 `GetUserChoiceTool` 挂起 (Suspend) 智能体推理循环，处理结构化用户选项中断并在接收输入后无缝恢复 (Resume) 上下文的人机协同 (HITL) 示例。
