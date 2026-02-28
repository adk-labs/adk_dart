# ADK Dart Porting Note (planners, agents)

- Date: 2026-02-28
- Scope:
  - `lib/src/planners/*`
  - `lib/src/agents/*`
  - `lib/src/tools/mcp_tool/mcp_session_manager.dart`
  - related tests
- Source reference window: `adk-python` daily reports `2026-02-23` ~ `2026-02-27`

## 1. Planners parity

- `BuiltInPlanner`
  - `thinkingConfig`를 필수 생성자 파라미터로 조정.
  - 요청에 기존 thinking config가 있을 때 overwrite 로그 유지.
- `PlanReActPlanner`
  - function call 그룹 보존 조건을 Python과 동일하게 조정:
    - 첫 function call index가 `0`인 경우 trailing function call을 추가 수집하지 않음.

## 2. Agents runtime parity

- `BaseAgent.runLive`
  - `runLiveImpl` 이후 `endInvocation`가 `true`여도 `afterAgentCallback`이 실행되도록 조정.
- `SequentialAgent.runLiveImpl`
  - live handoff용 `task_completed` 도구 주입 로직 추가.
  - LLM 서브에이전트에 1회만 도구/가이드 인스트럭션이 붙도록 중복 방지.
- `LlmAgent._maybeSaveOutputToState`
  - `outputSchema + outputKey`가 설정된 경우 final text를 JSON decode하여 state에 저장.
  - final chunk가 공백/빈 문자열이면 schema parse를 건너뜀.

## 3. Agents config / MCP parity

- `config_agent_utils`
  - built-in agent class를 short name/FQN 모두에서 동일하게 해석하도록 정규화 로직 추가.
  - custom agent factory를 `customAgentFactories` 뿐 아니라 resolver symbol에서도 찾도록 보강.
- `McpInstructionProvider`
  - MCP prompt 호출 시 context state 전체를 넘기지 않고,
    `prompts/list`에 정의된 인자 이름만 필터링하여 전달.
- `McpSessionManager`
  - `listPromptArgumentNames(...)` 추가 (prompt 정의 인자명 조회).

## 4. Verification

- Ran tests:
  - `test/planners_parity_test.dart`
  - `test/base_agent_callbacks_test.dart`
  - `test/workflow_agents_test.dart`
  - `test/llm_agent_output_state_test.dart`
  - `test/remote_a2a_agent_parity_test.dart`
  - `test/base_agent_live_fallback_test.dart`
  - `test/agent_config_parity_test.dart`
  - `test/mcp_http_integration_test.dart`
  - `test/agents_streaming_and_mcp_instruction_test.dart`
  - `test/flow_processors_parity_test.dart`
