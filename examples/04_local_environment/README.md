# Local Environment Example

이 예제는 ADK 에이전트에게 로컬 터미널 명령어 실행 및 파일 I/O 시스템 접근 권한을 가진 **로컬 실행 환경(LocalEnvironment)** 툴셋을 제공하는 방법을 보여줍니다.

## 주요 개념
- **EnvironmentToolset**: 에이전트가 로컬 또는 컨테이너화된 환경에서 명령어를 실행할 수 있도록 통합 도구들을 제공합니다 (예: 파일 생성, 파일 읽기/쓰기, 쉘 명령어 실행 등).
- **LocalEnvironment**: 에이전트가 실행되는 로컬 머신의 호스트 쉘 및 파일 시스템 환경을 연동합니다.

## 실행 방법

### 1. API 키 설정
```bash
export GEMINI_API_KEY="your-gemini-api-key"
```

### 2. 예제 실행
```bash
dart pub get
dart run bin/main.dart
```
