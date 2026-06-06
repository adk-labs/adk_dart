# Session DB Path Duplication Fix (2026-03-04)

## 배경
- 증상: `.../adk_dart/Users/.../test_app/.adk/session.db` 형태의 중첩 경로가 생성됨.
- 영향: 로컬 세션 DB가 의도한 에이전트 디렉터리가 아니라 잘못된 중첩 경로에 생성되어 세션 저장/조회 경로 일관성이 깨짐.

## 작업 단위 1: 원인 분석
- `web_server`의 앱 매핑(`appNameToDir`) 값이 절대경로(`entity.path`)로 채워짐.
- `PerAgentDatabaseSessionService`는 해당 값을 앱 폴더명으로 가정하고 `agentsRoot`에 다시 결합함.
- 결과적으로 `agentsRoot + absolutePath` 형태가 되어 경로가 중첩됨.

## 작업 단위 2: 코드 패치
- 파일: `lib/src/cli/utils/local_storage.dart`
- 변경:
  - 절대경로 판별 헬퍼 `_isAbsolutePath` 추가.
  - `PerAgentDatabaseSessionService._getService`에서:
    - 키가 절대경로이면 `createLocalDatabaseSessionService(baseDir: key)`를 직접 사용.
    - 상대경로/앱명일 때만 기존 `dotAdkFolderForAgent(agentsRoot + appName)` 로직 유지.
- 기대 결과:
  - 절대경로 매핑 입력 시 `agentsRoot` 재결합이 발생하지 않음.
  - 기존 상대경로 동작은 그대로 유지됨.

## 작업 단위 3: 회귀 테스트 추가
- 파일: `test/cli_service_factory_test.dart`
- 테스트 케이스 추가:
  - `appNameToDir`에 절대경로를 넣고 세션 생성 시,
    - `mappedAgentDir/.adk/session.db` 생성 확인.
    - `agentsRoot/<absolutePath>/.adk/session.db` 미생성 확인.

## 검증
- 실행 명령:
  - `dart test test/cli_service_factory_test.dart`
- 결과:
  - 신규 테스트 포함 전체 통과 (`All tests passed`).
