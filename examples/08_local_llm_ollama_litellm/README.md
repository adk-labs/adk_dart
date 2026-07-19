# Local LLM Example (Ollama / LiteLLM)

이 예제는 ADK Dart의 `LiteLlm` 모델 어댑터를 사용하여 로컬 머신에서 실행 중인 **Ollama** 또는 **LiteLLM 프록시** 서비스와 연동해 완전한 오프라인/로컬 에이전트를 구동하는 방법을 보여줍니다.

## 주요 개념
- **LiteLlm**: OpenAI-compatible 규격을 준수하는 모델 허브 및 프록시용 공용 모델 어댑터입니다.
- **Ollama 연동**: Ollama가 기본 제공하는 OpenAI 호환 API 엔드포인트(`http://localhost:11434/v1`)에 직접 연결하여 `gemma2`, `llama3` 등 로컬 모델을 구동합니다.
- **LiteLLM 연동**: 여러 로컬 및 리모트 모델 서비스를 대형 프록시 라우터(`http://localhost:4000/v1`) 형태로 통합 제공할 때 유용하게 연동할 수 있습니다.

## 실행 방법

### 1. 로컬 Ollama 구동 및 모델 다운로드
먼저 로컬에 Ollama가 설치되어 있어야 하며 백그라운드에 구동 중이어야 합니다.
그 후 터미널을 열어 원하는 모델을 로컬로 내려받습니다 (예: `gemma2:2b`).
```bash
ollama pull gemma2:2b
```

### 2. 환경 변수 구성 (선택)
기본 엔드포인트 및 모델 외의 설정을 변경하려면 아래 환경 변수를 오버라이드합니다.
```bash
# 기본값은 http://localhost:11434/v1 (Ollama)
export LOCAL_LLM_BASE_URL="http://localhost:11434/v1"
export LOCAL_LLM_MODEL="ollama_chat/gemma2:2b"
```

### 3. 예제 실행
```bash
dart pub get
dart run bin/main.dart
```
