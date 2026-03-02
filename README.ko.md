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

## 플랫폼 지원 매트릭스 (현재)

상태 표기:

- `✅` 지원
- `⚠️` 부분 지원/환경 의존
- `❌` 미지원

| 기능/표면 | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | 비고 |
| --- | --- | --- | --- | --- |
| `package:adk_dart/adk_dart.dart` 전체 API | ✅ | ⚠️ | ❌ | 전체 표면에는 `dart:io`/`dart:ffi`/`dart:mirrors` 경로 포함 |
| `package:adk_dart/adk_core.dart` Web-safe API | ✅ | ✅ | ✅ | IO/FFI/mirrors 의존 API 제외 |
| Agent 런타임 (`Agent`, `Runner`, workflows) | ✅ | ✅ | ✅ | In-memory 실행 경로는 크로스플랫폼 |
| MCP Streamable HTTP | ✅ | ✅ | ✅ | Web은 MCP 서버 CORS 설정 필요 가능 |
| MCP stdio (`StdioConnectionParams`) | ✅ | ⚠️ | ❌ | 로컬 프로세스 실행 필요, Web 불가 |
| inline Skills (`Skill`, `SkillToolset`) | ✅ | ✅ | ✅ | 웹에서도 사용 가능 |
| 디렉토리 스킬 로딩 (`loadSkillFromDir`) | ✅ | ⚠️ | ❌ | Web에서 `UnsupportedError` |
| CLI (`adk create/run/web/api_server/deploy`) | ✅ | ❌ | ❌ | 터미널/VM 전용 |
| Dev Web Server + A2A 엔드포인트 | ✅ | ❌ | ❌ | 서버 런타임 경로 |
| DB/파일 기반 서비스 (sqlite/postgres/mysql, file artifacts) | ✅ | ⚠️ | ❌ | IO/네트워크/파일시스템 제약 영향 |

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
