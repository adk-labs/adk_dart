# Managed Agent Basic Example

이 예제는 ADK 2.0의 관리형 에이전트 인터페이스인 `ManagedAgent`를 사용하여 Google GenAI Interactions API(interactions.create)와 연동하고 서버사이드 도구를 활용하는 기본 방법을 보여줍니다.

## 주요 개념
- **ManagedAgent**: 로컬에서 모델 루프를 직접 실행하지 않고, Google GenAI Managed Agents API를 통해 원격으로 에이전트의 세션을 조율합니다.
- **Server-side Tools**: `ManagedAgent`는 현재 서버에서 자체 실행되는 서버사이드 도구(예: `googleSearch`)만을 지원합니다.
- **Remote Sandbox**: 에이전트를 위해 원격 샌드박스를 프로비저닝하여, 멀티턴 대화 중에도 동일한 상태가 유지될 수 있도록 지원합니다.

## 실행 방법

### 1. API 키 설정
실제 Interactions API 호출을 위해 `GEMINI_API_KEY` 설정이 필요합니다.
```bash
export GEMINI_API_KEY="your-gemini-api-key"
```

### 2. 에이전트 ID 설정 (선택)
사용하려는 원격 Managed Agent의 ID를 설정합니다. 기본값은 `antigravity-preview-05-2026`입니다.
```bash
export MANAGED_AGENT_ID="projects/YOUR_PROJECT/locations/global/agents/YOUR_AGENT"
```

### 3. 예제 실행
```bash
dart pub get
dart run bin/main.dart
```
