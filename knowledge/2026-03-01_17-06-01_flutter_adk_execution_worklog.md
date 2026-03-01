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
- 상태: 완료

### 수행 시각
- 2026-03-01 17:46~18:00 KST

### 구현 내용
- 패키지 동기화 검사 확장:
  - `tool/check_package_sync.dart`
  - `packages/flutter_adk`에 대해 다음 항목 검증 추가:
    - 패키지 존재/이름(`flutter_adk`)
    - 버전 = 루트 `adk_dart` 버전
    - `adk_dart` 의존 버전 동기화
    - `lib/flutter_adk.dart`의 `adk_core` re-export 존재
- CI 워크플로우 확장:
  - `.github/workflows/package-sync.yml`
  - 기존 Dart sync job에 `adk_core` web compile smoke 추가
  - 신규 `flutter-adk-check` job 추가:
    - `flutter pub get`
    - `flutter analyze --no-pub`
    - `flutter test --no-pub`

### 검증 결과
- `dart run tool/check_package_sync.dart`: 통과
- `./tool/check_adk_core_web_compile.sh`: 통과
- `flutter analyze --no-pub` (`packages/flutter_adk`): 통과
- `flutter test --no-pub` (`packages/flutter_adk`): 통과

### 단위 결론
- `flutter_adk` 분리 이후 회귀를 막는 최소 CI/동기화 가드를 확보.

## Work Unit 5 — 플랫폼 지원/제한 매트릭스 문서화
- 상태: 완료

### 수행 시각
- 2026-03-01 18:20~18:35 KST

### 구현 내용
- 플랫폼 지원 매트릭스 문서 신규 작성:
  - `knowledge/2026-03-01_18-20-00_flutter_adk_platform_support_matrix.md`
  - `as-is`/`to-be`를 분리해 플랫폼별 지원 상태와 제한을 명시
  - BYOK(API 키 입력/저장/주입) 정책 및 보안 주의사항 포함
- `flutter_adk` README 제한사항 명시:
  - `packages/flutter_adk/README.md`
  - 현재 export 범위(`adk_core` only)와 Web 제한 안내

### 검증 결과
- 문서 변경 단위로 런타임 동작 변경 없음.
- 기존 코드/CI 게이트 설정과 충돌 없음 확인.

### 단위 결론
- “flutter_adk 단일 import 목표” 대비 현재 상태와 제한 사항이 명시되어,
  사용자 기대치 관리와 다음 구현 단위 합의가 가능한 상태.

## Work Unit 6 — flutter_adk Web Lite 런타임 export 확장
- 상태: 완료

### 수행 시각
- 2026-03-01 18:35~19:20 KST

### 구현 내용
- `adk_core` export 확장:
  - `Agent/LlmAgent`, `Runner/InMemoryRunner`, `FunctionTool`, `BaseLlm`, `Gemini`
  - 파일: `lib/adk_core.dart`
- Web 컴파일 차단 요인 정리:
  - 모델/환경 유틸의 `dart:io` 직접 의존 제거
  - 조건부 환경 리더 추가:
    - `lib/src/utils/system_environment/system_environment.dart`
    - `lib/src/utils/system_environment/system_environment_io.dart`
    - `lib/src/utils/system_environment/system_environment_stub.dart`
  - 수정 파일:
    - `lib/src/utils/env_utils.dart`
    - `lib/src/utils/client_labels_utils.dart`
    - `lib/src/utils/vertex_ai_utils.dart`
    - `lib/src/models/google_llm.dart`
    - `lib/src/models/apigee_llm.dart`
    - `lib/src/models/gemini_rest_api_client.dart`
- `LlmAgent`의 Web 비호환 import 경로 정리:
  - `discovery_engine_search_tool` 직접 의존 제거
  - `VertexAiSearchTool` bypass 경로는 self tool 반환으로 유지
- smoke/test 강화:
  - `tool/smoke/adk_core_web_smoke.dart`에 `Agent/Runner/Gemini` 참조 추가
  - `packages/flutter_adk/test/flutter_adk_test.dart`에
    `Agent/Runner` 실행 및 `Gemini` 심볼 테스트 추가
- Flutter 앱 import 충돌/의존성 보정:
  - `packages/flutter_adk/lib/flutter_adk.dart`에서
    Flutter `State` 충돌 방지를 위해 `hide State` 적용
  - `packages/flutter_adk/example/pubspec_overrides.yaml` 추가
    (로컬 최신 `adk_dart`를 예제가 참조하도록 고정)
- sync 체크 정책 보정:
  - `tool/check_package_sync.dart`
  - `flutter_adk` 버전은 루트와 동일 core 버전(빌드 메타데이터 허용),
    `adk_dart` 의존은 exact 또는 caret 허용

### 검증 결과
- `dart analyze` (수정 파일): 통과
- `./tool/check_adk_core_web_compile.sh`: 통과
- `flutter analyze --no-pub` (`packages/flutter_adk`): 통과
- `flutter test --no-pub` (`packages/flutter_adk`): 통과
- `flutter build web` (`packages/flutter_adk/example`): 통과
- `dart run tool/check_package_sync.dart`: 통과 (정책 보정 후)

### 단위 결론
- `flutter_adk` 단일 import로 `Agent/Runner/Gemini`까지 접근 가능한
  Web Lite 런타임 기반이 확보됨.

## Work Unit 7 — flutter_adk example 챗봇 UX 구현
- 상태: 완료

### 수행 시각
- 2026-03-01 19:20~19:45 KST

### 구현 내용
- `packages/flutter_adk/example/lib/main.dart`를 기본 플러그인 샘플에서
  실제 챗봇형 예제로 전면 교체:
  - 채팅 UI(버블, 입력창, 전송 버튼)
  - 설정 시트에서 Gemini API 키 입력/저장/삭제
  - `Agent + InMemoryRunner + Gemini + FunctionTool` 실행
  - 수도 조회 툴(`get_capital_city`) 포함
- API 키 저장을 위해 example 의존성 추가:
  - `packages/flutter_adk/example/pubspec.yaml`
  - `shared_preferences`
- widget test를 챗봇 셸 기준으로 업데이트:
  - `packages/flutter_adk/example/test/widget_test.dart`
- example 문서 갱신:
  - `packages/flutter_adk/example/README.md`

### 검증 결과
- `flutter analyze --no-pub` (`packages/flutter_adk/example`): 통과
- `flutter test --no-pub` (`packages/flutter_adk/example`): 통과
- `flutter build web` (`packages/flutter_adk/example`): 통과

### 단위 결론
- `flutter_adk` 예제가 “실제 챗봇 형태”로 동작하며,
  Flutter Web 포함 멀티플랫폼 실행 경로를 확인했다.

## Work Unit 8 — example 2단계 구성(기본 + Multi-Agent) 적용
- 상태: 완료

### 수행 시각
- 2026-03-01 20:00~20:25 KST

### 검토 결과
- `flutter_adk` 현재 공개 surface 기준으로 공식 문서 MAS의
  `Coordinator/Dispatcher` 패턴은 적용 가능.
  - 사용 가능: `Agent(LlmAgent)`, `subAgents`, 자동 `transfer_to_agent`
- `SequentialAgent/ParallelAgent/LoopAgent`는 현재 `flutter_adk` export에
  직접 노출되어 있지 않아 이번 예제 범위에서는 제외.

### 구현 내용
- 기존 챗봇 예제를 `Basic Chatbot`으로 유지하고,
  두 번째 예제로 `Multi-Agent Coordinator` 추가:
  - 파일: `packages/flutter_adk/example/lib/main.dart`
  - 상단 세그먼트 전환 UI 추가 (`Basic Chatbot` / `Multi-Agent`)
  - API 키 설정/저장은 공통으로 유지
  - 각 예제는 독립 Runner 세션 사용
- Multi-Agent 예제 구성:
  - root: `HelpDeskCoordinator`
  - sub-agent: `Billing`, `Support`
  - 라우팅 방식: `transfer_to_agent` 기반
- example 문서/테스트 갱신:
  - `packages/flutter_adk/example/README.md`
  - `packages/flutter_adk/example/test/widget_test.dart`

### 검증 결과
- `flutter analyze --no-pub` (`packages/flutter_adk/example`): 통과
- `flutter test --no-pub` (`packages/flutter_adk/example`): 통과
- `flutter build web` (`packages/flutter_adk/example`): 통과

### 단위 결론
- example 앱이 “기본 예제 + 공식 문서 기반 Multi-Agent 예제” 2단계 구조로 확장되었고,
  Flutter Web 포함 실행 가능 상태를 확인했다.

## Work Unit 9 — Workflow/MCP/Skills flutter_adk surface 확장
- 상태: 완료

### 수행 시각
- 2026-03-01 20:30~21:20 KST

### 문제 인식
- 기존 `flutter_adk`는 transfer 기반 Multi-Agent 예제는 가능했지만,
  `Sequential/Parallel/Loop` 노출이 빠져 공식 workflow-agent 예제 적용 범위가 제한됨.
- MCP/Skills는 코어 구현이 존재해도 Web compile 경로에서 `dart:io` 의존으로
  `flutter_adk` surface에 포함되지 못함.

### 구현 내용
- `adk_core` export 확장:
  - Workflow agents: `SequentialAgent`, `ParallelAgent`, `LoopAgent`
  - MCP: `McpToolset`, `McpTool`, `mcp_session_manager`, `load_mcp_resource_tool`
  - Skills: `SkillToolset`, `skill_runtime`
- `adk_mcp` Web 경로 정리:
  - `mcp_remote_client.dart`의 `dart:io` 의존 제거
    - HTTP/SSE 처리 경로를 `package:http` 기반으로 변경
    - `HttpException` 상속 제거, 커스텀 예외 문자열화
  - stdio는 플랫폼 분리:
    - `packages/adk_mcp/lib/src/mcp_stdio_client_stub.dart` 추가
    - `packages/adk_mcp/lib/adk_mcp.dart`를 조건부 export로 전환
- Skills Web 경로 정리:
  - `lib/src/skills/skill_web.dart` 추가 (inline skill 중심, dir-loader는 Unsupported)
  - `lib/src/skills/skill_runtime.dart` 추가 (조건부 export)
  - `skill_toolset.dart`가 `skill_runtime.dart`를 사용하도록 전환
- example 앱 확장:
  - 기존 `Basic Chatbot`, `Multi-Agent` 유지
  - 신규 `Workflow` 예제 추가 (`Sequential + Parallel + Loop`)
- 문서/스모크/테스트 갱신:
  - `tool/smoke/adk_core_web_smoke.dart`
  - `packages/flutter_adk/test/flutter_adk_test.dart`
  - `packages/flutter_adk/example/README.md`
  - `packages/flutter_adk/README.md`
  - 플랫폼 매트릭스 문서 갱신

### 검증 결과
- `dart format`: 통과
- `dart analyze`: 통과
- `./tool/check_adk_core_web_compile.sh`: 통과
- `flutter analyze --no-pub` (`packages/flutter_adk`): 통과
- `flutter test --no-pub` (`packages/flutter_adk`): 통과
- `flutter analyze --no-pub` (`packages/flutter_adk/example`): 통과
- `flutter test --no-pub` (`packages/flutter_adk/example`): 통과
- `flutter build web` (`packages/flutter_adk/example`): 통과

### 단위 결론
- `flutter_adk` 단일 import로 workflow agents를 직접 사용할 수 있게 되었고,
  MCP/Skills도 Web 포함 멀티플랫폼에서 사용할 수 있는 surface가 확보됨.
- 단, Web에서는 MCP stdio 및 directory-based skill loading은 정책적으로 미지원이며,
  문서에 명시했다.
