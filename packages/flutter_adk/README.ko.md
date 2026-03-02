# flutter_adk

[English](README.md) | 한국어 | [日本語](README.ja.md) | [中文](README.zh.md)

Flutter 앱에서 ADK Dart 코어 런타임을 Web-safe 표면으로 사용하기 위한 파사드 패키지입니다.

## 제공 항목

- `package:adk_dart/adk_core.dart` 재노출
- Flutter 단일 import 경로: `package:flutter_adk/flutter_adk.dart`
- 주요 Flutter 플랫폼(Android/iOS/Web/Linux/macOS/Windows) 플러그인 등록

## 언제 `flutter_adk`를 쓰면 좋나요?

`flutter_adk`를 선택하세요:

- Flutter 앱에서 모바일/데스크톱/Web을 하나의 import로 다루고 싶을 때
- VM 전용 API를 기본으로 끌어오지 않고 Web-safe `adk_core` 표면을 쓰고 싶을 때

다른 패키지를 선택하세요:

- VM/CLI 에이전트/도구/서버 개발: `adk_dart` (짧은 import는 `adk`)

설계 의도:

- `flutter_adk`는 단순 래퍼 이름이 아니라 Flutter 호환 계층입니다.
- 전체 VM 전용 API를 그대로 노출하기보다 Web-safe 런타임 표면(`adk_core`)을
  중심으로 제공해 Flutter 멀티플랫폼에서 동작 일관성을 우선합니다.

## 플랫폼 지원 매트릭스 (현재)

상태 표기:

- `Y` 지원
- `Partial` 주의사항과 함께 지원
- `N` 미지원

| 기능 | Android | iOS | Web | Linux | macOS | Windows | 비고 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `flutter_adk` 단일 import | Y | Y | Y | Y | Y | Y | Web-safe `adk_core` 표면 재노출 |
| Agent 런타임 (`Agent`, `Runner`, workflows) | Y | Y | Y | Y | Y | Y | in-memory 경로는 공통 |
| `Gemini` 모델 사용 | Y | Y | Partial | Y | Y | Y | Web BYOK/CORS/보안 정책 고려 필요 |
| MCP Toolset (Streamable HTTP) | Y | Y | Y | Y | Y | Y | 원격 MCP HTTP 서버 연결 |
| MCP Toolset (stdio) | Partial | Partial | N | Y | Y | Y | Web 불가, 모바일은 프로세스 정책 영향 가능 |
| Skills (inline) | Y | Y | Y | Y | Y | Y | 인라인 스킬은 크로스플랫폼 |
| 디렉토리 스킬 로딩 (`loadSkillFromDir`) | Y | Y | N | Y | Y | Y | Web에서 `UnsupportedError` |
| 플러그인 채널 helper (`getPlatformVersion`) | Y | Y | Y | Y | Y | Y | 플랫폼 채널 / 브라우저 user-agent |
| VM/CLI 도구 (`adk`, dev server, deploy path) | N | N | N | N | N | N | Flutter 패키지 범위 밖 |

## 사용 예

```dart
import 'package:flutter_adk/flutter_adk.dart';
```

## 참고

- 상세 기능/제약: [README.md](README.md)
- 플랫폼 심화 노트: `knowledge/2026-03-01_18-20-00_flutter_adk_platform_support_matrix.md`
