# 2026-03-28 Python Latest Sync

검토 범위

- `ref/adk-python` `2a90fbc1..f9736738`

작업 단위

1. Local environment toolset parity
- 작업 내용
  - `EnvironmentToolset`, `BaseEnvironment`, `LocalEnvironment`를 추가했다.
  - Python upstream과 같은 이름의 `Execute`, `ReadFile`, `EditFile`, `WriteFile` 도구를 제공하도록 구현했다.
  - 작업 디렉터리 기준 경로 정규화와 workspace escape 차단을 넣었다.
  - `processLlmRequest()`에서 환경 규칙 instruction을 주입하도록 맞췄다.
  - 사용 예시로 `example/local_environment_agent.dart`를 추가했다.
  - 파일 I/O, 명령 실행, instruction 주입, 경로 차단을 검증하는 회귀 테스트를 추가했다.
- 작업 이유
  - Python upstream `9082b9e3`, `f9736738`는 `EnvironmentToolset`과 `LocalEnvironment`를 새로 추가했다.
  - Dart에는 기존 `ExecuteBashTool`만 있었고, 파일 읽기/쓰기/수정과 환경 규칙 instruction을 포함하는 통합 surface가 없어서 parity gap이 있었다.

2. Toolset failure tolerance parity
- 작업 내용
  - `LlmAgent.canonicalTools()` 내부의 toolset resolve 경로를 완화해서, 개별 toolset이 예외를 던져도 전체 tool resolution이 실패하지 않고 나머지 도구는 계속 사용되도록 바꿨다.
  - 해당 동작을 고정하는 회귀 테스트를 추가했다.
- 작업 이유
  - Python upstream `5df03f1f`는 toolset 하나의 실패가 전체 agent tool resolution을 깨지 않도록 바뀌었다.
  - Dart는 예외를 그대로 전파하고 있어서, 복수 tool/toolset을 함께 쓰는 구성에서 parity gap이 있었다.

3. Agent Registry MCP destination metadata parity
- 작업 내용
  - Agent Registry에서 생성하는 MCP toolset을 전용 subclass로 감싸고, 각 tool의 `customMetadata`에 `gcp.mcp.server.destination.id`를 주입하도록 바꿨다.
  - registry metadata에서 `mcpServerId`를 읽어 tool metadata로 전달하는 회귀 테스트를 추가했다.
- 작업 이유
  - Python upstream `67547608`는 Agent Registry MCP tool에 destination resource ID metadata를 싣도록 바뀌었다.
  - Dart는 MCP endpoint 연결까지만 맞춰져 있었고, downstream telemetry나 라우팅에서 쓸 수 있는 식별 metadata는 빠져 있었다.

4. Streaming function-call ID parity
- 작업 내용
  - `StreamingResponseAggregator`가 LLM이 function call ID를 주지 않는 경우에도 ADK client ID를 생성해서 progressive / non-progressive aggregation 결과에 유지하도록 보강했다.
  - 기존 aggregator parity 테스트에 ID 보장 assertion을 추가했다.
- 작업 이유
  - Python upstream `fe418171`는 streaming function call 처리 중 ID가 비어 있을 때 ADK 쪽에서 ID를 생성하도록 수정됐다.
  - Dart 런타임은 최종 event finalize 단계에서 ID를 채우는 경로가 있었지만, aggregator 자체를 직접 쓰는 경로에서는 parity gap이 남아 있었다.

5. Agent loader discovery and validation parity
- 작업 내용
  - `AgentLoader.listAgents()`가 non-hidden 디렉터리만 나열하고, agent definition 유효성 검사는 load 단계에서만 하도록 바꿨다.
  - `loadAgent()`에 agent name validation을 추가해서 `.` / `/` / 공백 / `-` / 상대경로 형태 이름을 거부하고, 실제 단일 앱 alias 또는 하위 디렉터리가 존재하는 경우에만 로드를 허용하도록 보강했다.
  - single-app root alias가 `listAgentsDetailed()`에서도 같은 해석 규칙을 쓰도록 경로 판별 로직을 공통화했다.
  - directory listing, load rejection, single-app alias metadata를 고정하는 회귀 테스트를 추가했다.
- 작업 이유
  - Python upstream `50209549`는 `list_agents()`를 단순 directory discovery로 바꾸고, load 가능 여부 판단은 실제 로드 경로로 미뤘다.
  - Python upstream `116f75d2`는 agent name validation을 추가해 임의 module/path import를 막았다.
  - Dart는 review 시점까지 discovery와 validation이 섞여 있었고, single-app root에서 임의 alias를 허용하는 gap이 남아 있었다.

직접 포팅하지 않은 항목

- `database_session_service`의 concurrent insert patch: Dart SQLite / network DB 구현은 이미 state row upsert 기반이라, Python patch가 막는 중복 state insert race를 구조적으로 흡수하고 있었다.
- release workflow / version bump / docs tooling 변경: Dart 저장소의 릴리스 체계와 직접 연결되지 않아 포팅 대상에서 제외했다.
- `tools.environment` README 샘플 문서: Dart는 별도 contributing sample 디렉터리 대신 `example/` 예제로 대응했다.

검증

- `dart format` on changed files
- `dart analyze lib test example`
- `dart test`
  - `test/environment_toolset_parity_test.dart`
  - `test/llm_agent_toolset_parity_test.dart`
  - `test/agent_registry_parity_test.dart`
  - `test/utils_missing_parity_test.dart`
  - `test/cli_agent_loader_test.dart`
