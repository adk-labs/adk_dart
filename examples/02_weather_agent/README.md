# Weather Agent Example (Function Calling)

이 예제는 ADK Dart 에이전트에 사용자 정의 함수 도구(`FunctionTool`)를 바인딩하고 실행하는 방법을 보여줍니다. 에이전트가 서울 날씨에 관한 질문을 받았을 때 자동으로 해당 날씨 조회 API(함수)를 호출하여 답변을 구성합니다.

## 주요 개념
- **FunctionTool**: Dart 함수(`getWeather`)를 에이전트의 LLM 도구 호출 규격에 맞춰 어댑팅합니다.
- **Automatic Function Calling**: 에이전트가 날씨 정보를 필요로 할 때, LLM이 반환하는 Tool Call 요청을 감지하여 정의된 Dart 함수를 직접 실행하고 그 결과를 LLM에 응답으로 전달하는 전 과정이 자동화되어 처리됩니다.

## 실행 방법

### 1. API 키 설정
이 예제는 실제 Gemini API 모델(`gemini-2.5-flash`)을 사용합니다. 먼저 `GEMINI_API_KEY` 환경 변수를 등록해야 합니다.
```bash
export GEMINI_API_KEY="your-gemini-api-key"
```

### 2. 예제 실행
```bash
dart pub get
dart run bin/main.dart
```
