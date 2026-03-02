# Dart용 Agent Development Kit (ADK) (`adk`)

[English](README.md) | 한국어 | [日本語](README.ja.md) | [中文](README.zh.md)

`adk`는 `adk_dart`를 짧은 import 경로로 재노출하는 파사드 패키지입니다.

## 역할

- 짧은 import: `package:adk/adk.dart`
- `adk_dart` API 재노출
- `adk` CLI 엔트리포인트 제공

## 플랫폼 지원 매트릭스 (현재)

상태 표기:

- `✅` 지원
- `⚠️` 부분 지원/환경 의존
- `❌` 미지원

| 기능/표면 | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | 비고 |
| --- | --- | --- | --- | --- |
| `package:adk/adk.dart` facade import | ✅ | ⚠️ | ❌ | `adk_dart` 전체 API 표면을 재노출 |
| `adk` CLI 실행 파일 | ✅ | ❌ | ❌ | VM/터미널 전용 |
| facade 경유 런타임/도구 기능 (MCP, skills, sessions 등) | ✅ | ⚠️ | ❌ | 실제 제약은 `adk_dart`와 동일 |
| Web-safe 전용 엔트리포인트 제공 | ❌ | ❌ | ❌ | Web-safe 표면은 `adk_dart/adk_core.dart` 또는 `flutter_adk` 사용 |

## 설치

```bash
dart pub add adk
```

## 참고

- 상세 기능: [README.md](README.md)
- 코어 패키지: <https://pub.dev/packages/adk_dart>
