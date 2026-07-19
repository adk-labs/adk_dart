# On-Device Gemma Example (LiteRT-LM)

이 예제는 ADK Dart와 **`adk_litertlm`** 서브 패키지를 사용하여 디바이스 내부에서 직접 **Gemma 온디바이스 모델**을 실행하고 대화를 수행하는 온디바이스 AI 에이전트 구동을 보여줍니다.

## 주요 개념
- **LiteRtLmModel**: TensorFlow Lite의 거대 언어 모델 구동 라이브러리인 LiteRT-LM을 기반으로 설계된 디바이스 내장형 LLM 어댑터입니다.
- **On-Device LLM Execution**: 클라우드 API 호출 및 네트워크 지연 없이 기기 내부의 CPU/NPU 자원을 활용해 Gemma 인퍼런스를 로컬에서 직접 처리합니다.

## 실행 방법

### 1. Gemma 온디바이스 모델 다운로드
Kaggle Models 등의 플랫폼에서 `gemma-2b-it-cpu-int4.bin` 또는 호환되는 LiteRT Gemma `.bin` 가중치 파일을 다운로드합니다.

### 2. 환경 변수로 모델 파일 경로 지정
```bash
export LITERT_MODEL_PATH="/your/local/path/to/gemma-2b-it-cpu-int4.bin"
```

### 3. 예제 실행
```bash
dart pub get
dart run bin/main.dart
```
