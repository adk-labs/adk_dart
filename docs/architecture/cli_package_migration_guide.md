# ADK CLI Package Migration & Architecture Guide

이 문서는 `adk_dart` 코어 패키지 내부에 포함된 CLI/웹서버 로직을 `packages/adk` 독립 패키지로 안전하게 이전하기 위한 아키텍처 설계 및 마이그레이션 가이드입니다.

---

## 1. 아키텍처 목표 (Target Architecture)

```
[ adk_dart ] (Core SDK Library)
  │  - Agent, Runner, Workflow 2.0, LLM Providers, Tools, Sessions
  │  - 외부 CLI/웹서버 의존성 제거로 SDK 경량화
  │
  └───► [ packages/adk ] (CLI Toolchain & Unified Entrypoint)
          │  - depends on: adk_dart, shelf, args, etc.
          │  - bin/adk.dart (CLI Executable)
          │  - lib/src/cli/ (adk create, run, web, deploy, eval)
          │  - lib/src/browser/ (Angular/Web UI 번들)
```

---

## 2. 파일별 이전 매핑 테이블 (File Mapping)

| 원본 위치 (`adk_dart`) | 대상 위치 (`packages/adk`) | 비고 |
| :--- | :--- | :--- |
| `lib/src/dev/cli.dart` | `packages/adk/lib/src/cli/dev_cli.dart` | CLI 메인 파서 및 서브커맨드 핸들러 |
| `lib/src/dev/web_server.dart` | `packages/adk/lib/src/cli/web_server.dart` | Dev 웹서버 런타임 |
| `lib/src/dev/project.dart` | `packages/adk/lib/src/cli/project.dart` | 프로젝트 스캐폴딩 유틸리티 |
| `lib/src/cli/*` | `packages/adk/lib/src/cli/*` | `cli_create`, `cli_deploy`, `cli_eval` 등 |
| `lib/src/cli/browser/*` | `packages/adk/lib/src/browser/*` | Web UI 정적 에셋 |

---

## 3. 하위 호환성 유지 전략 (Backward Compatibility)

기존에 `package:adk_dart/cli.dart`를 참조하던 외부 코드나 레거시 테스트의 중단을 방지하기 위해 다음 전략을 적용합니다:

1. **브릿지 익스포트 유지**:
   `adk_dart/lib/cli.dart` 파일에 즉시 삭제 대신 Deprecation 안내와 함께 `packages/adk`의 진입점을 연동하거나 핵심 러너만 유지합니다.
2. **독립 CLI 바이너리**:
   `dart pub global activate adk`를 통해 전역 명령어로 실행되는 표준 진입점은 `packages/adk/bin/adk.dart`로 단일화합니다.

---

## 4. 단계별 마이그레이션 실행 체크리스트

- [ ] **Step 1. 의존성 설정**:
  `packages/adk/pubspec.yaml`에 필요한 의존성(`shelf`, `shelf_router`, `shelf_static`, `shelf_web_socket` 등) 명시
- [ ] **Step 2. 파일 이전**:
  `lib/src/cli/` 및 `lib/src/dev/` 내 CLI 파일들을 `packages/adk/lib/src/cli/`로 이동
- [ ] **Step 3. import 경로 정리**:
  이전된 파일들에서 `../agents/`, `../runners/` 등으로 되어 있던 상대 경로를 `package:adk_dart/adk_dart.dart` 패키지 import로 전환
- [ ] **Step 4. 테스트 이전 및 검증**:
  `test/dev_web_server_test.dart`, `test/cli_*_test.dart`를 `packages/adk/test/`로 이전 후 `dart test` 실행
- [ ] **Step 5. 패키지 배포 및 버전 동기화**:
  `pubspec.yaml` 버전 동기화 및 `dart analyze` 검증 완료

---

## 5. 결론 및 기대 효과

- **SDK 사용자**: 불필요한 서버/CLI 의존성 없이 가볍고 빠른 에이전트 개발 가능
- **CLI 사용자**: `adk` 패키지만으로 풍부한 툴체인(`adk create`, `adk run`, `adk web`, `adk deploy`) 완벽 지원
- **패키지 정체성**: pub.dev 및 오픈소스 생태계에서 100% 명확한 역할 분담 및 완성도 확보
