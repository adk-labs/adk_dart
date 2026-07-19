# Multi-Agent and Google Search Example

이 예제는 ADK Dart에서 **단일 에이전트의 구글 검색 도구 활용** 및 **멀티 에이전트 간의 전환(Hand-off)** 오케스트레이션을 보여줍니다.

## 주요 개념

### 1. 단일 에이전트 구글 검색
- **googleSearch**: Gemini 모델과 연동되는 구글 검색 도구입니다. 에이전트가 사용자의 질문에 답하기 위해 신뢰성 있는 최신 정보가 필요할 때 자동으로 검색을 진행합니다.

### 2. 멀티 에이전트 오케스트레이션
- **greeter**: 사용자의 일상 인사와 스몰토크를 처리하는 전담 에이전트입니다.
- **task_executor**: 검색 도구를 사용하여 복잡한 정보 수집이나 실행 작업을 처리하는 전담 에이전트입니다.
- **coordinator**: 사용자 입력의 의도에 맞게 적절한 서브 에이전트(`greeter` 또는 `task_executor`)로 제어권을 넘겨주는 라우터 역할을 수행합니다.

## 실행 방법

### 1. API 키 설정
실제 구글 검색 도구 및 Gemini 모델을 사용하므로 `GEMINI_API_KEY` 환경 변수가 필요합니다.
```bash
export GEMINI_API_KEY="your-gemini-api-key"
```

### 2. 예제 실행
```bash
dart pub get
dart run bin/main.dart
```
