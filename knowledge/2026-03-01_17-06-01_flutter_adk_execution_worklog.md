# flutter_adk 착수 실행 로그 (2026-03-01)

## 목적
- 기준 문서:
  - `knowledge/2026-02-28_18-38-11_flutter_adk_all_platform_checklist.md`
  - `knowledge/2026-02-28_21-44-13_adk_core_split_plan.md`
  - `knowledge/2026-03-01_16-59-24_flutter_adk_all_platform_plan.md`
- 사용자 요청: 작업 단위별 문서화 + 작업 단위별 커밋/푸시

## Work Unit 1 — 최신 베이스라인 재확인

### 수행 시각
- 2026-03-01 17:06:01 KST

### 확인 결과
- 루트 버전: `adk_dart` `2026.3.1`
- `lib/adk_dart.dart` export 수: `358`
- `lib/src` 내 `dart:io` direct import 파일 수: `83`
- `lib/adk_dart.dart`가 직접 export하는 `dart:io` 파일 수: `54`
- `dart:ffi` 사용 파일:
  - `lib/src/sessions/sqlite_session_service.dart`
  - `lib/src/sessions/migration/sqlite_db.dart`
- `dart:mirrors` 사용 파일:
  - `lib/src/dev/web_server.dart`
- `lib/adk_core.dart`: 없음
- `packages/flutter_adk`: 없음
- CI: `.github/workflows/package-sync.yml` 단일 워크플로우(Flutter/Web gate 없음)

### 단위 결론
- 계획서 가정은 여전히 유효하며, 착수 순서는 `adk_core` 분리(Phase 1) 선행이 맞음.

## Work Unit 2 — adk_core 분리 산출물 구현
- 상태: 완료
- 목표:
  - `lib/adk_core.dart`
  - `knowledge/adk_core_api_matrix.md`
  - `tool/smoke/adk_core_web_smoke.dart`
  - `tool/check_adk_core_web_compile.sh`

### 수행 시각
- 2026-03-01 17:06~17:36 KST

### 구현 내용
- `lib/adk_core.dart` 신설:
  - Flutter/Web-safe 엔트리포인트 추가
  - core 화이트리스트 export 구성
- `knowledge/adk_core_api_matrix.md` 작성:
  - 포함/제외 API 그룹화
  - Web-safe 제외 규칙 명시
- `tool/smoke/adk_core_web_smoke.dart` 작성:
  - `adk_core` import + 최소 타입 참조 스모크
- `tool/check_adk_core_web_compile.sh` 작성:
  - `dart compile js` 단일 게이트 커맨드 고정

### 추가 수정(게이트 실패 원인 제거)
- Web JS 비호환 정수 리터럴 제거:
  - `lib/src/agents/run_config.dart`
  - `lib/src/auth/auth_tool.dart`
  - `lib/src/tools/openapi_tool/openapi_spec_parser/tool_auth_handler.dart`
  - `lib/src/models/gemini_context_cache_manager.dart`
- FNV64/64bit 처리 로직을 `BigInt` 기반 signed-int64 래핑으로 교체해 기존 해시 결과를 유지.
- 회귀 방지 테스트 추가:
  - `test/credential_manager_test.dart`에 known payload hash 고정값 검증 추가.

### 검증 결과
- `dart analyze` (core/관련 수정 파일): 통과
- `dart test test/credential_manager_test.dart test/runner_live_config_test.dart`: 통과
- `./tool/check_adk_core_web_compile.sh`: 통과
  - `Compiled ... to ... JavaScript` 확인

### 단위 결론
- `adk_core` 분리 산출물과 Web compile smoke gate를 확보했으며, Phase 2(`packages/flutter_adk` 스캐폴드)로 진행 가능한 상태.

## Work Unit 3 — flutter_adk 패키지 스캐폴드
- 상태: 완료

### 수행 시각
- 2026-03-01 17:18~17:46 KST

### 구현 내용
- `packages/flutter_adk` 신규 생성 (`flutter create --template=plugin`)
  - 플랫폼 등록: Android, iOS, Web, Linux, macOS, Windows
- 메타데이터/릴리스 정렬:
  - `packages/flutter_adk/pubspec.yaml`
  - 버전 `2026.3.1`
  - repository/homepage/issue tracker/topics 설정
- `adk_core` facade 연결:
  - `packages/flutter_adk/lib/flutter_adk.dart`에서
    `export 'package:adk_dart/adk_core.dart';` 추가
- 문서/릴리스 노트 정리:
  - `packages/flutter_adk/README.md`
  - `packages/flutter_adk/CHANGELOG.md`
- 테스트 보강:
  - `packages/flutter_adk/test/flutter_adk_test.dart`
  - `adk_core` 심볼 export 스모크 케이스 추가

### 의존성 정렬
- `adk_dart: 2026.3.1` 명시
- 로컬 미배포 API(`adk_core.dart`) 참조를 위해 임시로
  `dependency_overrides`에 `adk_dart: path: ../..` 추가

### 검증 결과
- `flutter analyze --no-pub` (`packages/flutter_adk`): 통과
- `flutter test --no-pub` (`packages/flutter_adk`): 통과

### 단위 결론
- `flutter_adk` 6플랫폼 스캐폴드와 core facade 경로를 확보했으며,
  다음 단위는 CI/sync 규칙 확장(Work Unit 4) 진행 가능.

## Work Unit 4 — CI/동기화 규칙 확장
- 상태: 진행 예정
