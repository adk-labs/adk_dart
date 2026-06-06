# 2026-04-08 Python Latest Sync

검토 범위

- `ref/adk-python` `f9736738..23bd95bc`

작업 단위

1. Skill script argument parity
- 작업 내용
  - `run_skill_script` 스키마에 `short_options`, `positional_args`를 추가했다.
  - Python/shell wrapper 생성 시 long option, short option, positional argument를 모두 materialize 하도록 바꿨다.
  - positional argument가 있을 때 `--` separator를 넣도록 맞췄다.
  - 잘못된 타입 입력에 대해 `INVALID_SHORT_OPTIONS_TYPE`, `INVALID_POSITIONAL_ARGS_TYPE` 회귀 테스트를 추가했다.
- 작업 이유
  - Python upstream `2b49163b`는 `RunSkillScriptTool`이 short option과 positional argument를 지원하도록 확장됐다.
  - Dart는 기존에 long option용 `args`만 지원하고 있어 skill script parity gap이 있었다.

2. BashTool safety/config parity
- 작업 내용
  - `BashToolPolicy`에 `blockedOperators`, `timeoutSeconds`를 추가했다.
  - 실행 전 blocked operator를 검사하도록 바꿨다.
  - timeout을 policy 값으로 제어하고, 출력이 없을 때 placeholder 문자열을 반환하도록 맞췄다.
  - blocked operator와 timeout 회귀 테스트를 추가했다.
- 작업 이유
  - Python upstream `1b058424`, `f641b1a2`, `23bd95bc`는 BashTool에 추가 safety/config surface를 넣었다.
  - Dart는 prefix allowlist만 있었고, 메타문자 차단과 configurable timeout parity가 빠져 있었다.

3. Public auth provider registration parity
- 작업 내용
  - `BaseAuthProvider.supportedAuthSchemes`를 추가했다.
  - `CredentialManager.registerGlobalAuthProvider()`를 추가해 provider가 선언한 scheme들로 전역 등록할 수 있게 했다.
  - manager 인스턴스는 local registry 우선, 없으면 global registry를 fallback으로 조회하도록 바꿨다.
  - global registration이 새 manager에서도 바로 보이는 회귀 테스트를 추가했다.
- 작업 이유
  - Python upstream `a2209105`는 custom auth provider를 공개 API로 등록하는 경로를 추가했다.
  - Dart는 인스턴스별 수동 등록만 가능해서, 샘플/앱 초기화 단계에서 한 번 등록하고 재사용하는 parity가 부족했다.

4. Web server app metadata parity
- 작업 내용
  - `/apps/{app_name}/app-info` endpoint를 추가했다.
  - root agent가 `LlmAgent`인 경우 nested agent tree와 tool declaration을 직렬화해서 반환하도록 구현했다.
  - plain Dart function tool은 reflection 기반 이름 추론으로 `functionDeclarations`에 노출되게 했다.
  - `/list-apps?detailed=true` 응답 키를 `rootAgentName`, `isComputerUse` 형태로 정리했다.
  - list-apps/app-info/non-LLM error 회귀 테스트를 추가했다.
- 작업 이유
  - Python upstream `da438faf`는 app metadata inspection endpoint를 추가했다.
  - Dart는 app summary까지만 제공하고 있어서, CLI/web tooling이 agent tree와 tool surface를 introspect하는 parity가 빠져 있었다.

직접 포팅하지 않은 항목

- BashTool resource limits / process-group hard kill: Dart 표준 `Process` API만으로는 Python의 RLIMIT / process-group 제어를 동일하게 옮기기 어려워 이번 배치에서는 blocked operator와 timeout surface만 반영했다.
- trigger routes / Secret Manager / BigQuery skill assets: Python 쪽은 새 CLI 및 integration surface가 크고 Dart 저장소 구조와 직접 1:1 대응되지 않아 별도 배치로 분리했다.

검증

- `dart format` on changed files
- `dart analyze lib test example`
  - 에러 없이 통과, 기존 info-level lint만 남음
- `dart test`
  - `test/skill_toolset_parity_test.dart`
  - `test/bash_tool_parity_test.dart`
  - `test/credential_manager_test.dart`
- `dart test`
  - `test/dev_web_server_test.dart --plain-name "startAdkDevWebServer serves list-apps endpoint"`
  - `test/dev_web_server_test.dart --plain-name "startAdkDevWebServer serves app info endpoint with nested llm agents and tools"`
  - `test/dev_web_server_test.dart --plain-name "startAdkDevWebServer returns bad request for non-llm app info roots"`
- 참고
  - `test/dev_web_server_test.dart` 전체 실행은 이번 변경과 무관한 기존 실패 2건이 남아 있다.
  - `loads extra plugin via dynamic file-path class spec`
  - `retries and drains persisted a2a push deliveries after server restart`
