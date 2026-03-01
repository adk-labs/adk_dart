# flutter_adk 플랫폼 지원/제한 매트릭스 (2026-03-01)

## 문서 목적
- Flutter 앱 개발자가 `package:flutter_adk/flutter_adk.dart` 단일 import로 어떤 기능을 어디까지 사용할 수 있는지 현재 상태와 목표 상태를 명확히 기록한다.
- 플랫폼별 제한 사항을 사전에 고지하고, 회피 전략과 다음 구현 단위를 정의한다.

## 기준 스냅샷 (as-is)
- `packages/flutter_adk`는 현재 `adk_core`만 re-export.
- `adk_core`는 Web-safe 화이트리스트로 제한되어 `LlmAgent`, `Runner`, `Gemini`를 포함하지 않음.
- `lib/src` 기준:
  - `dart:io` import 파일: `83`
  - `dart:ffi` import 파일: `2`
  - `dart:mirrors` import 파일: `1`
- `Gemini` 구현(`lib/src/models/google_llm.dart`)은 `dart:io`를 직접 import.

## 현재 지원 매트릭스 (flutter_adk 단일 import 기준)

| 기능 영역 | Android | iOS | Web | Linux | macOS | Windows | 비고 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `adk_core` 데이터/세션/메모리 기본 타입 | Supported | Supported | Supported | Supported | Supported | Supported | `adk_core` web compile smoke 게이트 통과 |
| `LlmAgent`/`Agent` 생성 | Not supported | Not supported | Not supported | Not supported | Not supported | Not supported | 현재 `flutter_adk` export 범위 밖 |
| `Runner`/`InMemoryRunner` 실행 | Not supported | Not supported | Not supported | Not supported | Not supported | Not supported | 현재 `flutter_adk` export 범위 밖 |
| `Gemini` 모델 직접 호출 | Not supported | Not supported | Not supported | Not supported | Not supported | Not supported | 현재 `flutter_adk` export 범위 밖 |
| CLI/dev server 계열 기능 | Not supported | Not supported | Not supported | Not supported | Not supported | Not supported | Flutter 런타임 대상 아님 |

## 참고: adk_dart 직접 import 시 플랫폼 특성
- `package:adk_dart/adk_dart.dart`를 직접 import하면 일부 기능은 모바일/데스크톱에서 동작할 수 있으나, Web은 `dart:io`/`dart:ffi`/`dart:mirrors` 제약으로 전체 기능 parity가 불가능하다.
- 즉, 현재 “모든 플랫폼에서 동일 동작” 목표는 `flutter_adk` 쪽에서 별도 계층 정리가 필요하다.

## 목표 지원 매트릭스 (to-be, flutter_adk vNext)

| 기능 영역 | Android | iOS | Web | Linux | macOS | Windows | 정책 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `LlmAgent`/`Runner` 기본 실행 경로 | Supported | Supported | Supported | Supported | Supported | Supported | flutter_adk 단일 import 보장 |
| HTTP 기반 모델 호출(예: Gemini) | Supported | Supported | Supported | Supported | Supported | Supported | 웹 안전 HTTP 경로 필요 |
| In-memory 세션/아티팩트/메모리 | Supported | Supported | Supported | Supported | Supported | Supported | 공통 기본 런타임 |
| FFI/sqlite 기반 세션 | Supported | Supported | Not supported | Supported | Supported | Supported | Web은 명시적 `UnsupportedError` |
| 로컬 프로세스/CLI/dev server | Not supported | Not supported | Not supported | Not supported | Not supported | Not supported | Flutter 패키지 범위에서 제외 |

## API 키 입력/저장(BYOK) 정책
- 목표: 앱 설정 화면에서 API 키를 입력받아 런타임에 모델 생성 시 주입 가능.
- 모바일/데스크톱: 안전 저장소 사용 권장(예: secure storage 계열).
- 웹: 브라우저 저장소 키 노출 리스크를 문서에 명시하고, 프로덕션 권장 경로는 서버 프록시 사용.

## 필수 제한사항 문구(문서/README 공통)
- `flutter_adk`는 플랫폼별 미지원 기능을 컴파일 에러가 아닌 런타임 `UnsupportedError`로 명시해야 한다.
- Web에서 로컬 파일/프로세스/FFI 계열 기능은 지원하지 않는다.
- Web BYOK는 가능하더라도 보안상 공개 서비스 기본값으로 권장하지 않는다.

## 다음 구현 단위 (권장 순서)
1. `flutter_adk` export 확장 (`Agent`/`Runner`/tool 기본 계층).
2. 모델 계층의 web-safe 분리(`dart:io` 직접 의존 제거 또는 조건부 경로).
3. 플랫폼별 `UnsupportedError` 가드 표준화.
4. Flutter Web 예제(BYOK 입력/저장/실행) 추가.
5. CI에 `flutter build web` + runtime smoke 게이트 추가.
