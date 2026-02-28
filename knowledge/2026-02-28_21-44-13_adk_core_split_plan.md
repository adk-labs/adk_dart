# adk_core 분리 실행 계획서

## 0) 문서 목적
- `adk_dart`에서 Flutter/Web-safe 진입점(`lib/adk_core.dart`)을 신설한다.
- 기존 VM/CLI 사용자(`package:adk_dart/adk_dart.dart`, `package:adk/`)를 깨지 않고 유지한다.
- 이후 `packages/flutter_adk`가 의존할 안정적인 core API 경로를 확정한다.

## 1) 현황 스냅샷 (2026-02-28 기준)
- 현재 `lib/adk_dart.dart` export 수: `352`
- 그중 직접 `dart:io` import 파일 export 수: `45`
- `lib/src` 기준 `dart:io` direct import 총 `71`건
- `dart:io` 집중 영역(파일 수 기준):
  - `cli` 15, `tools` 13, `evaluation` 6, `code_executors` 5, `utils` 4, `sessions` 4
- CI 현황: `.github/workflows/package-sync.yml`는 Dart 테스트/패키지 sync만 수행(Flutter/Web compile gate 없음)

근거 파일:
- `lib/adk_dart.dart`
- `tool/check_package_sync.dart`
- `.github/workflows/package-sync.yml`

## 2) 목표 / 비목표

목표:
- `lib/adk_core.dart` 추가
- `adk_core` import 경로에서 web 컴파일 성공 보장
- core 포함/제외 API 문서화
- 기존 `adk_dart.dart` API 동작 유지

비목표(본 단계):
- `dart:io` 의존 71건 즉시 제거
- CLI/로컬 파일/로컬 프로세스 기반 기능의 Web 즉시 지원
- `packages/flutter_adk` 구현 완료(별도 단계)

## 3) 아키텍처 결정

결정 1: 엔트리포인트 분리
- `lib/adk_core.dart`: Flutter/Web-safe 화이트리스트 export
- `lib/adk_dart.dart`: 기존 full export 유지(레거시 호환)

결정 2: core 후보 선정 방식
- 1차: direct `dart:io` file 제외
- 2차: web compile gate(`dart compile js`) 실패 시 transitive 의존 역추적 후 제외
- 3차: 제외 항목은 명시적 표로 기록(대체 경로 포함)

결정 3: 점진 이행
- 대규모 리팩터링 대신 “컴파일 게이트 기반 축소/복원” 전략 사용
- API break를 유발하는 rename/remove는 피하고 entrypoint만 추가

## 4) 구현 범위 (파일 단위)

신규:
- `lib/adk_core.dart`
- `tool/check_adk_core_web_compile.sh` (또는 동등 Dart 스크립트)
- `tool/smoke/adk_core_web_smoke.dart` (core import 전용 최소 스모크)
- `knowledge/adk_core_api_matrix.md` (포함/제외/사유 표)

수정:
- `README.md` (`adk_core` 사용 가이드, 어떤 경우 `adk_dart` 사용해야 하는지)
- `tool/check_package_sync.dart` (`adk_core` 검증 규칙 추가 여부)
- `.github/workflows/package-sync.yml` (선택: web compile gate 추가)

## 5) 단계별 실행 계획

### Phase A: API 인벤토리 고정 (반나절)
- `lib/adk_dart.dart` export를 카테고리별 분류
- direct `dart:io` 포함 export 45개 우선 제외 후보로 마킹
- 산출물: `knowledge/adk_core_api_matrix.md` v1

완료 기준:
- core 포함 후보 / 제외 후보 / 보류 후보가 모두 표로 존재

### Phase B: `adk_core.dart` 초안 생성 (반나절)
- `lib/adk_core.dart` 생성
- 안전군(export whitelist)만 우선 노출
- `adk_dart.dart`는 변경 최소화(기존 그대로 유지)

완료 기준:
- `dart analyze` 통과
- 기존 `package:adk_dart/adk_dart.dart` import 사용자에게 breaking 없음

### Phase C: Web 컴파일 게이트 도입 (반나절)
- `tool/smoke/adk_core_web_smoke.dart` 작성:
  - `import 'package:adk_dart/adk_core.dart';`
  - 최소 타입 참조 1~2개
- 검증 커맨드 고정:
  - `dart compile js tool/smoke/adk_core_web_smoke.dart -o /tmp/adk_core_smoke.js`
- 실패 시 transitive `dart:io` 경로를 역추적해 `adk_core.dart` export 조정

완료 기준:
- web compile gate 녹색
- 재현 가능한 단일 커맨드 문서화 완료

### Phase D: 문서/릴리스 가드 정리 (반나절)
- README에 entrypoint 선택 가이드 추가
- core 제외 기능의 대체 경로 명시
- 필요 시 CI에 gate 연결(초기에는 optional 잡으로 시작 가능)

완료 기준:
- 사용자 문서에서 `adk_core`와 `adk_dart` 선택 기준이 명확

## 6) PR 분할 제안

PR-1: 인벤토리 + `adk_core.dart` 초안
- 범위: `lib/adk_core.dart`, matrix 문서
- 목표: API 분리의 최소 골격 확보

PR-2: Web compile gate
- 범위: smoke 파일 + check 스크립트 + (선택) CI optional 잡
- 목표: 회귀 방지 장치 추가

PR-3: 문서 및 sync 규칙
- 범위: README, 체크 스크립트 확장
- 목표: 사용성/유지보수성 마무리

## 7) 리스크와 대응

리스크 1: direct `dart:io`가 없어도 transitive로 web compile 실패
- 대응: compile gate 우선, 실패 로그 기반으로 export 축소

리스크 2: core에서 빠진 API로 사용자 혼선
- 대응: `adk_core` 제외표 + 대체 import 가이드 제공

리스크 3: `packages/adk`와의 facade 정책 충돌
- 대응: 초기에는 `packages/adk` 유지, `flutter_adk`에서만 `adk_core` 사용

## 8) 승인 필요 의사결정
- `adk_dart.dart`를 장기적으로 full API 유지할지, 향후 `adk_io.dart`로 재배치할지
- `package:adk/`가 향후 `adk_core`를 병행 export할지 여부
- Web에서 공식적으로 제외할 기능 목록 확정 범위

## 9) 착수 체크리스트
- [ ] `adk_core` export 화이트리스트 1차안 작성
- [ ] `adk_core_web_smoke.dart` 추가
- [ ] `dart compile js` gate 통과
- [ ] README entrypoint 가이드 반영
- [ ] 체크리스트 문서(`flutter_adk_all_platform_checklist`)와 상태 동기화
