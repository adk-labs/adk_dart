# Echo Agent Example

이 예제는 ADK Dart 패키지를 사용하여 간단한 에이전트를 초기화하고 실행하는 기본 구조를 보여줍니다.

## 주요 개념
- **BaseLlm**: 사용자 정의 LLM 모델 인터페이스를 구현합니다 (`EchoModel`은 사용자의 마지막 입력을 그대로 에코하는 더미 모델입니다).
- **Agent**: 에이전트의 이름, 설명 및 LLM 모델을 정의합니다.
- **InMemoryRunner**: 인메모리 세션 및 메모리 서비스를 사용하는 간단한 에이전트 실행기입니다.
- **Session**: 사용자 세션을 생성하고 이력을 보존합니다.

## 실행 방법
1. 의존성 설치:
   ```bash
   dart pub get
   ```
2. 예제 실행:
   ```bash
   dart run bin/main.dart
   ```
