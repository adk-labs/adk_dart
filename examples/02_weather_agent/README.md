# 02. Weather Agent (Tool Calling)

Demonstrates how to bind external Dart functions to an agent using `FunctionTool` and execute automated tool calls via Gemini.

## How to Run

```bash
cd examples/02_weather_agent
dart pub get
export GEMINI_API_KEY="your-gemini-api-key"
dart run bin/main.dart
```

---

### 한국어
`FunctionTool`을 사용하여 일반 Dart 함수(날씨 조회 함수)를 에이전트 도구로 등록하고 Gemini 모델이 자동으로 도구를 호출(Tool Calling)하도록 하는 예제입니다.

### 日本語
`FunctionTool` を使用して Dart 関数をエージェントツールとしてバインドし、Gemini による自動ツール呼び出し (Tool Calling) を実行するサンプルです。

### 中文
使用 `FunctionTool` 将 Dart 函数绑定为智能体工具，并通过 Gemini 自动执行工具调用 (Tool Calling) 的示例。
