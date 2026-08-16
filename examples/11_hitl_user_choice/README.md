# 11. Human-In-The-Loop (Interactive Choices)

Demonstrates Human-In-The-Loop (HITL) workflows where the agent pauses execution to request structured user choices via `GetUserChoiceTool` before proceeding.

## How to Run

```bash
cd examples/11_hitl_user_choice
dart pub get
export GEMINI_API_KEY="your-gemini-api-key"
dart run bin/main.dart
```

---

### 한국어
`GetUserChoiceTool`을 활용하여 에이전트가 실행 중 사용자에게 선택 옵션을 제시하고, 사용자의 선택 결과를 받아 다음 작업을 이어가는 인터랙티브 HITL 예제입니다.

### 日本語
`GetUserChoiceTool` を活用し、エージェントが実行中にユーザーへ選択肢を提示して結果を受け取り、次の処理へ進むインタラクティブな HITL サンプルです。

### 中文
利用 `GetUserChoiceTool` 演示智能体在执行过程中向用户提供结构化选项并在获取用户选择后继续执行的人机协同 (HITL) 示例。
