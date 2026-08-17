# adk_litertlm

[English](README.md) | 한국어 | [日本語](README.ja.md) | [中文](README.zh.md)

ADK Dart 패키지용 LiteRT-LM 모델 통합 패키지입니다.

이 패키지는 [LiteRT-LM](https://pub.dev/packages/litertlm) 온디바이스 모델을 ADK Dart 에이전트 런타임에 연결하는 `LiteRtModel` 구현을 제공하여 완전한 오프라인 온디바이스 AI 에이전트 실행을 가능하게 합니다.

## 주요 기능

- **온디바이스 추론**: LiteRT-LM 모델을 사용하여 완전히 기기 내에서 에이전트를 실행합니다.
- **ADK 런타임 통합**: `LlmAgent` 및 전체 ADK 파이프라인과 호환되는 드롭인 `BaseLlm` 구현을 제공합니다.
- **스트리밍 지원**: 실시간 토큰 단위 스트리밍 응답을 지원합니다.

## 설치

```bash
dart pub add adk_litertlm
```

또는 `pubspec.yaml`:

```yaml
dependencies:
  adk_litertlm: ^2026.8.17+1
```

## 시작하기

```dart
import 'package:adk_litertlm/adk_litertlm.dart';

final model = LiteRtModel(modelPath: 'path/to/model.tflite');
final agent = LlmAgent(name: 'local-agent', model: model);
```

## ADK 2.0 호환성

이 패키지는 ADK 2.0과 정렬되어 있어, v2 워크플로(선언적 노드 그래프 스케줄링) 및 하이브리드 온디바이스 + 클라우드 실행을 위한 Managed Agent 연동을 지원합니다.
