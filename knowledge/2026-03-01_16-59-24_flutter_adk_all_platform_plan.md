# flutter_adk 멀티플랫폼 지원 재검토 실행 계획서 (2026-03-01)

## 0) 문서 목적
- 기준 문서:
  - `knowledge/2026-02-28_18-38-11_flutter_adk_all_platform_checklist.md`
  - `knowledge/2026-02-28_21-44-13_adk_core_split_plan.md`
- 최신 코드베이스(`adk_dart` `2026.3.1`) 기준으로 Flutter 6개 플랫폼(Android, iOS, Web, Linux, macOS, Windows) 지원 계획을 재정의한다.
- 목표는 "즉시 전체 기능 parity"가 아니라 "컴파일 가능한 core 경로 + flutter_adk 패키지 + 회귀 방지 게이트"를 순차적으로 확보하는 것이다.

## 1) 최신 현황 스냅샷 (2026-03-01 16:59 KST)
- 패키지 버전:
  - `adk_dart`: `2026.3.1`
  - `adk`: `2026.3.1`
  - `adk_mcp`: `2026.3.1`
- `lib/adk_dart.dart` export 수: `358`
- `lib/src` 내 `dart:io` direct import 파일 수: `83`
- `lib/adk_dart.dart`가 직접 export하는 `dart:io` 파일 수: `54`
- `dart:io` 집중 영역(파일 수):
  - `tools 23`, `cli 15`, `sessions 7`, `evaluation 6`, `telemetry 5`, `code_executors 5`
- `dart:ffi` import 파일:
  - `lib/src/sessions/sqlite_session_service.dart`
  - `lib/src/sessions/migration/sqlite_db.dart`
- `dart:mirrors` import 파일:
  - `lib/src/dev/web_server.dart`
- 미구현 상태:
  - `lib/adk_core.dart` 없음
  - `packages/flutter_adk` 없음
- CI 상태:
  - `.github/workflows/package-sync.yml`만 존재
  - Flutter/Web compile gate 없음

## 2) 사실 기반 문제 정의
- 현재 `package:adk_dart/adk_dart.dart`는 transitive 의존으로 `dart:ffi`와 `dart:mirrors`를 끌어오므로 Web 컴파일 불가.
- 실제 확인 커맨드:
  - `dart compile js tool/_tmp_web_smoke.dart -o /tmp/adk_web_smoke.js`
- 주요 실패 원인:
  - `dart:ffi` (`sqlite_session_service.dart`, `sqlite3` FFI 경로)
  - `dart:mirrors` (`dev/web_server.dart`)
- 결론:
  - `flutter_adk`를 시작하려면 먼저 `adk_core` 엔트리 분리가 선행되어야 한다.

## 3) 목표와 비목표

### 목표
- `lib/adk_core.dart` 신설 및 Web-safe export 화이트리스트 확정
- `packages/flutter_adk` 플러그인 스캐폴드 생성 및 6개 플랫폼 등록
- 최소 스모크 게이트 도입:
  - `adk_core` Web 컴파일
  - `flutter_adk` analyze/test
- CI에 Flutter 체크 단계 추가

### 비목표 (초기 릴리스)
- `dart:io` 83개를 즉시 제거
- CLI/로컬 파일/로컬 프로세스 기능의 Web 완전 지원
- 기존 `adk_dart.dart` full export 정책 즉시 폐기

## 4) 아키텍처 원칙
- 원칙 1: 엔트리포인트 분리
  - `adk_dart.dart`: 레거시/full 유지
  - `adk_core.dart`: Flutter/Web-safe만 노출
- 원칙 2: API 호환 우선
  - 기존 VM/CLI 사용자에게 breaking change를 만들지 않는다.
- 원칙 3: 게이트 중심 점진 이행
  - "리팩터링 선행"이 아니라 "컴파일 게이트 통과"를 우선으로 export를 좁혀간다.

## 5) 실행 계획 (업데이트 버전)

### Phase 1: adk_core 분리 (선행 필수)
- 작업
  - `lib/adk_core.dart` 생성
  - `knowledge/adk_core_api_matrix.md` 작성
  - `tool/smoke/adk_core_web_smoke.dart` 추가
  - `tool/check_adk_core_web_compile.sh` 추가
- 제외 규칙
  - `dart:io`, `dart:ffi`, `dart:mirrors`, `Process`, 로컬 FS/HTTP 서버 직접 의존 API는 `adk_core`에서 제외
- 완료 기준
  - `dart analyze`
  - `dart compile js tool/smoke/adk_core_web_smoke.dart -o /tmp/adk_core_smoke.js` 통과

### Phase 2: flutter_adk 스캐폴드
- 작업
  - `packages/flutter_adk` 생성
  - Flutter plugin 플랫폼: `android, ios, web, linux, macos, windows`
  - `packages/flutter_adk/lib/flutter_adk.dart` 엔트리 정의
  - `packages/flutter_adk`가 `adk_core`만 의존하도록 구성
- 완료 기준
  - `flutter analyze packages/flutter_adk`
  - `flutter test packages/flutter_adk`
  - example 앱에서 core 실행 경로 확인

### Phase 3: 플랫폼 어댑터/폴백 정책
- 작업
  - 인증/토큰/저장소 adapter 인터페이스 정의
  - Web 미지원 기능에 대한 명시적 `UnsupportedError` 표준화
  - 최소 공통 런타임(in-memory 중심) 제공
- 완료 기준
  - 동일 public API가 6개 플랫폼에서 "컴파일" 가능
  - 미지원 기능은 런타임에서 예측 가능한 에러 메시지 제공

### Phase 4: CI 및 릴리스 파이프라인
- 작업
  - 신규 workflow 추가: Flutter analyze/test + adk_core web compile smoke
  - `tool/check_package_sync.dart` 확장:
    - `packages/flutter_adk` 버전/의존 동기화 검사
  - 릴리스 체크리스트 문서화
- 완료 기준
  - PR 기준 필수 게이트 녹색
  - 버전/체인지로그/동기화 규칙 자동 검증

## 6) PR 분할 제안
- PR-1: `adk_core` + API matrix + web smoke
- PR-2: `packages/flutter_adk` 스캐폴드 + example
- PR-3: adapter/fallback 정책 + 테스트 보강
- PR-4: CI/workflow + sync 규칙 확장

## 7) 리스크와 대응
- 리스크: transitive 의존으로 인한 Web 컴파일 재실패
  - 대응: smoke compile를 CI 필수 게이트로 승격
- 리스크: core에서 빠진 API로 사용자 혼선
  - 대응: `adk_core_api_matrix.md`에 대체 import 경로 명시
- 리스크: facade 정책 충돌 (`packages/adk` vs `flutter_adk`)
  - 대응: `adk`는 full re-export 유지, `flutter_adk`는 `adk_core` 의존으로 역할 분리

## 8) 의사결정 필요 항목
- `package:adk`에 `adk_core`를 병행 re-export할지 여부
- Web 공식 지원 범위(지원/미지원 기능 목록) 확정
- 초기 persistent storage 전략(in-memory only vs 플랫폼별 기본 구현) 확정

## 9) 즉시 착수 체크리스트
- [ ] `lib/adk_core.dart` 화이트리스트 초안 작성
- [ ] `knowledge/adk_core_api_matrix.md` v1 작성
- [ ] `tool/smoke/adk_core_web_smoke.dart` 추가
- [ ] `dart compile js` gate 통과
- [ ] `packages/flutter_adk` 스캐폴드 생성
- [ ] Flutter CI 단계 추가
