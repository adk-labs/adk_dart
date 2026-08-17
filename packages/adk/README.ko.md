# Dart용 Agent Development Kit (ADK) (`adk`)

[English](README.md) | 한국어 | [日本語](README.ja.md) | [中文](README.zh.md)

`adk`는 Dart용 Agent Development Kit (ADK)의 공식 CLI 툴체인 및 최상위 통합 엔트리포인트 패키지입니다.

글로벌/로컬 CLI 도구(`adk create`, `adk run`, `adk web`, `adk api_server`, `adk deploy`, `adk eval`)를 제공하며, `package:adk/adk.dart`를 통해 ADK의 모든 런타임 기능을 직관적으로 사용할 수 있도록 지원합니다.

## 주요 기능

- **CLI 툴체인 기본 제공**: `dart pub global activate adk`를 통해 터미널에서 `adk` 명령어를 즉시 실행
- **통합 SDK 엔트리포인트**: 에이전트, 워크플로우(Workflow 2.0), LLM 연동, 툴셋 API를 `import 'package:adk/adk.dart';`로 일원화
- **MCP 및 고성능 런타임 지원**: 최신 MCP(Model Context Protocol) 툴셋 및 멀티 에이전트 오케스트레이션 지원

## 생태계 패키지 구성 및 역할

- **`adk`** (본 패키지): CLI 실행 바이너리 및 서버/백엔드 Dart 환경을 위한 최상위 통합 엔트리포인트
- **`adk_dart`**: 에이전트 핵심 프리미티브, 오케스트레이터, 워크플로우 엔진을 제공하는 SDK 코어 라이브러리
- **`flutter_adk`**: Flutter 멀티플랫폼 앱을 위한 플랫폼 채널, Web-safe 런타임, UI 전용 플러그인
- **`adk_mcp`**: 표준 MCP 클라이언트 및 서버 확장을 위한 전용 패키지
- **`adk_litertlm`**: 모바일/온디바이스 Gemini Nano 및 LiteRT 가속을 위한 온디바이스 전용 패키지

## 언제 `adk`를 사용하나요?

`adk`를 선택하세요:

- 터미널에서 `adk` CLI 도구를 사용하고 싶을 때
- Dart VM, 백엔드 서버, CLI 에이전트 애플리케이션을 개발할 때

다른 패키지를 선택하세요:

- Flutter 클라이언트 앱(Mobile/Desktop/Web)을 개발할 때: `flutter_adk`
- SDK 코어 라이브러리에 직접 의존하는 모듈식 확장을 개발할 때: `adk_dart`

## 패키지 링크

- [adk](https://pub.dev/packages/adk): 짧은 import 경로
  (`package:adk/adk.dart`)를 제공하는 파사드 패키지입니다.
- [adk_dart](https://pub.dev/packages/adk_dart): 전체 ADK Dart VM/CLI
  런타임을 제공하는 코어 패키지입니다.
- [flutter_adk](https://pub.dev/packages/flutter_adk): Flutter
  멀티플랫폼에서 Web-safe ADK API를 제공하는 패키지입니다.

## 플랫폼 지원 매트릭스 (현재)

상태 표기:

- `Y` 지원
- `Partial` 부분 지원/환경 의존
- `N` 미지원

| 기능 / 영역 | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | 비고 |
| --- | --- | --- | --- | --- |
| `package:adk/adk.dart` facade import | Y | Partial | N | `adk_dart` 전체 API를 재노출 |
| `adk` CLI 실행 파일 | Y | N | N | VM/터미널 전용 |
| facade 경유 런타임/도구 기능 (MCP, skills, sessions 등) | Y | Partial | N | 실제 제약은 `adk_dart`와 동일 |
| Web-safe 전용 엔트리포인트 제공 | N | N | N | Web-safe API는 `adk_dart/adk_core.dart` 또는 `flutter_adk` 사용 |

## 설치

```bash
dart pub add adk
```

## 참고

- 상세 기능: [README.md](README.md)
- 코어 패키지: <https://pub.dev/packages/adk_dart>
