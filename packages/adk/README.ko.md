# Dart용 Agent Development Kit (ADK) (`adk`)

[English](README.md) | 한국어 | [日本語](README.ja.md) | [中文](README.zh.md)

`adk`는 `adk_dart`를 짧은 import 경로로 재노출하는 파사드 패키지입니다.

## 역할

- 짧은 import: `package:adk/adk.dart`
- `adk_dart` API 재노출
- `adk` CLI 엔트리포인트 제공

## 언제 `adk`를 쓰면 좋나요?

`adk`를 선택하세요:

- Dart VM/CLI 환경에서 짧은 import(`package:adk/adk.dart`)를 원할 때
- `adk_dart`와 동일 동작을 유지하면서 패키지 이름만 간결하게 쓰고 싶을 때

다른 패키지를 선택하세요:

- Flutter 앱 코드(특히 Web 포함): `flutter_adk`
- 코어 패키지명을 명시적으로 쓰고 싶다면: `adk_dart`

설계 의도:

- `adk`는 런타임 분기가 아니라 네이밍/사용성(짧은 import) 목적의 파사드입니다.
- 즉, `adk_dart`와 동일한 VM 중심 런타임을 더 간결한 패키지명으로 쓰고 싶을 때
  선택하는 패키지입니다.

## 플랫폼 지원 매트릭스 (현재)

상태 표기:

- `Y` 지원
- `Partial` 부분 지원/환경 의존
- `N` 미지원

| 기능/표면 | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | 비고 |
| --- | --- | --- | --- | --- |
| `package:adk/adk.dart` facade import | Y | Partial | N | `adk_dart` 전체 API 표면을 재노출 |
| `adk` CLI 실행 파일 | Y | N | N | VM/터미널 전용 |
| facade 경유 런타임/도구 기능 (MCP, skills, sessions 등) | Y | Partial | N | 실제 제약은 `adk_dart`와 동일 |
| Web-safe 전용 엔트리포인트 제공 | N | N | N | Web-safe 표면은 `adk_dart/adk_core.dart` 또는 `flutter_adk` 사용 |

## 설치

```bash
dart pub add adk
```

## 참고

- 상세 기능: [README.md](README.md)
- 코어 패키지: <https://pub.dev/packages/adk_dart>
