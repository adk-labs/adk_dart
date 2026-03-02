# Dart용 Agent Development Kit (ADK)

[English](README.md) | 한국어 | [日本語](README.ja.md) | [中文](README.zh.md)

ADK Dart는 AI 에이전트 개발/실행을 위한 코드 중심 Dart 프레임워크입니다.
에이전트 런타임, 툴 오케스트레이션, MCP 연동을 제공합니다.

## 핵심 기능

- 코드 중심 에이전트 런타임 (`BaseAgent`, `LlmAgent`, `Runner`)
- 이벤트 스트리밍 기반 실행
- 멀티 에이전트 구성 (`Sequential`, `Parallel`, `Loop`)
- Function/OpenAPI/Google API/MCP 도구 통합
- `adk` CLI (`create`, `run`, `web`, `api_server`, `deploy`)

## 어떤 패키지를 써야 하나요?

| 이런 경우 | 권장 패키지 | 이유 |
| --- | --- | --- |
| Dart VM/CLI 환경(서버, 도구, 테스트, 전체 런타임 API)에서 에이전트 개발 | `adk_dart` | ADK Dart의 전체 런타임 표면을 제공하는 기본 패키지 |
| VM/CLI 환경이지만 import 경로를 짧게 쓰고 싶음 | `adk` | `adk_dart`를 재노출하는 파사드 (`package:adk/adk.dart`) |
| Flutter 앱(Android/iOS/Web/Linux/macOS/Windows) 개발 | `flutter_adk` | `adk_core` 기반의 Flutter/Web-safe 표면을 단일 import로 제공 |

빠른 선택 기준:

- 기본값은 `adk_dart`
- 동작은 같고 이름만 짧게 쓰려면 `adk`
- Flutter 앱 코드(특히 Web 포함)면 `flutter_adk`

## 설계 철학

- `adk_dart`는 런타임/패리티 중심 코어 패키지입니다.
  ADK SDK 개념을 최대한 유지하면서 Dart VM 실행 경로에서 폭넓은
  기능 구현을 우선합니다.
- `adk`는 사용성(패키지명) 중심 파사드입니다.
  별도 런타임을 구현하지 않고 `adk_dart`를 짧은 이름으로 재노출합니다.
- `flutter_adk`는 Flutter 멀티플랫폼 계층입니다.
  Android/iOS/Web/Linux/macOS/Windows에서 하나의 Flutter 코드 경로를
  유지하도록 Web-safe 표면(`adk_core`)을 의도적으로 제공합니다.

용어 정리:

- 이 문서에서 `VM/CLI`는 Dart VM 프로세스(CLI 도구, 서버 프로세스, 테스트,
  Flutter가 아닌 Dart 데스크톱 앱)를 의미합니다.
- Flutter 데스크톱 UI 앱은 기본적으로 `flutter_adk` 사용을 권장합니다.

## 플랫폼 지원 매트릭스 (현재)

상태 표기:

- `Y` 지원
- `Partial` 부분 지원/환경 의존
- `N` 미지원

| 기능/표면 | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | 비고 |
| --- | --- | --- | --- | --- |
| `package:adk_dart/adk_dart.dart` 전체 API | Y | Partial | N | 전체 표면에는 `dart:io`/`dart:ffi`/`dart:mirrors` 경로 포함 |
| `package:adk_dart/adk_core.dart` Web-safe API | Y | Y | Y | IO/FFI/mirrors 의존 API 제외 |
| Agent 런타임 (`Agent`, `Runner`, workflows) | Y | Y | Y | In-memory 실행 경로는 크로스플랫폼 |
| MCP Streamable HTTP | Y | Y | Y | Web은 MCP 서버 CORS 설정 필요 가능 |
| MCP stdio (`StdioConnectionParams`) | Y | Partial | N | 로컬 프로세스 실행 필요, Web 불가 |
| inline Skills (`Skill`, `SkillToolset`) | Y | Y | Y | 웹에서도 사용 가능 |
| 디렉토리 스킬 로딩 (`loadSkillFromDir`) | Y | Partial | N | Web에서 `UnsupportedError` |
| CLI (`adk create/run/web/api_server/deploy`) | Y | N | N | 터미널/VM 전용 |
| Dev Web Server + A2A 엔드포인트 | Y | N | N | 서버 런타임 경로 |
| DB/파일 기반 서비스 (sqlite/postgres/mysql, file artifacts) | Y | Partial | N | IO/네트워크/파일시스템 제약 영향 |

## 설치

```bash
dart pub add adk_dart
```

짧은 import 패키지(`adk`)를 쓰려면:

```bash
dart pub add adk
```

## 문서

- 전체 기능 매트릭스/예제/세부 사용법: [README.md](README.md)
- 저장소: <https://github.com/adk-labs/adk_dart>
