# 2026-07-11 Post-Sync Gap Review & Flutter Example Expansion

## 기준

- `adk-python`: `57e1ba66` (HEAD, 오전 Managed Agent Sync와 동일 기준)
- 검토 윈도우: `e6df0979..57e1ba66` (2026-07-06 ~ 2026-07-10, 110 commits)
- 검토 방법: 서브시스템별(ManagedAgent / Workflow / Flows / Tools·Artifacts / Live·Plugins·기타) 병렬 대조 + LLM-facing 프롬프트 문자열 전수 비교

## 이번 작업에서 수정한 것

### 1. fc985492 포팅: single_turn 비-LlmAgent 서브에이전트 인라인 툴 래핑

- `lib/src/agents/llm_agent.dart` `_installModeSubAgentToolsIfNeeded`: `is! LlmAgent` 스킵을 제거하고, `mode`를 선언한 모든 에이전트(LlmAgent, ManagedAgent)가 래핑 대상에 참여하도록 완화. LlmAgent의 chat 기본값은 유지.
- `lib/src/flows/llm_flows/agent_transfer.dart` `_usesTaskTransferMode`: ManagedAgent의 `mode`도 확인해 single_turn/task ManagedAgent를 LLM transfer 대상에서 제외 (Python의 hasattr 기반 체크와 동일).
- 테스트: `test/managed_agent_parity_test.dart`에 wrapping/미래핑/transfer 제외/task 래핑 4건 추가 (Python `test_llm_agent_single_turn_subagents.py` 미러).

### 2. a680cea8 검증: node_input → user_content 브리지

- Python은 `ManagedAgent._run_impl` 오버라이드로 해결했지만, Dart는 `SingleTurnAgentTool` → `_runAgentInCurrentSession`이 `BaseAgent` 기반으로 tool args → `_nodeInputToContent` → `userContent` 브리징을 이미 수행하므로 기능상 동등. 코드 변경 없이 회귀 테스트로 고정: single-turn tool 호출 인자가 interactions payload의 `input`에 도달하는지 검증하는 테스트 추가.

### 3. b44d2c9d 포팅: 컴팩션 요약 프롬프트/포맷 갱신

- `lib/src/apps/llm_event_summarizer.dart`:
  - `_defaultPromptTemplate`을 Python 최신본으로 교체 (사용자 언어 명시 + 사용한 tool 이름 나열을 요구하는 CRITICAL INSTRUCTIONS 포함).
  - `formatEventsForPrompt`가 thought / function call / function response를 포함하도록 확장. 이전 컴팩션 이벤트의 thought는 제외.
  - tool args/response 렌더링을 2,000자로 캡하는 `_truncate` 추가 (`... [truncated N chars]` 마커).

### 4. 프롬프트 parity 정렬 (LLM-facing 문자열 전수 비교 결과 반영)

- `lib/src/tools/transfer_to_agent_tool.dart`: 설명을 Python docstring 원문("Transfer the query to another agent. Use this tool to hand off control...")으로 교체.
- `lib/src/tools/request_input_tool.dart`: 설명을 Python 원문("Ask the user a question and wait for their response. Use this when...")으로 교체하고 `response_schema` 파라미터 설명도 Python Args 원문으로 보강.
- 나머지 프롬프트는 전부 SAME 판정: agent transfer instructions, identity, load/preload memory, load artifacts, example few-shot 포맷, plan_re_act_planner, evaluation/user-simulator, get_user_choice 등.

### 5. Flutter 예제 보완 (`packages/flutter_adk/example`)

- `lib/adk_core.dart`에 `google_search_tool.dart` export 추가 (web-safe, url_context와 동일한 의존성).
- 신규 예제 2종 추가:
  - `Graph Workflow`: ADK 2.0 graph `Workflow` — triage `FunctionNode`가 `EventActions(route:)`로 라우팅하고 routed `Edge`가 기술/비즈니스/일반 전문 `AgentNode` 중 하나만 실행 (`DEFAULT_ROUTE` 폴백 포함).
  - `Google Search`: Gemini built-in `googleSearch` grounding 예제.
- `examples_registry.dart` 등록, `app_localizations.dart`에 en/ko/ja/zh 16키 추가, README 4개 언어판(카탈로그/지원 매트릭스/샘플 프롬프트) 갱신.

## 백로그 포팅 결과 (waves 1–3 + 마무리 포팅)

초기 gap 백로그를 3개 wave(P1–P6)로 병렬 포팅했고, 세션 한도로 중단된 wave-3 잔여분은
직접(Opus 4.8) 마무리했다. 최종 disposition은 아래와 같다.

### ✅ 포팅 완료 (테스트 포함)

보안/정합성:

- `8718aeff` + `f8631500` (net, `961f3e88` rollback 반영): artifact caller-scope 제한 + file service 경로 세그먼트 검증. cross-user artifact 접근 차단.
- `283e92ef`: resumable/live 경로에서 user-authored function call 거부 (model bypass 방지).

Workflow (그래프):

- `6af52715`: START발 routed edge 금지 검증.
- `8db2ace3`: 에러 종료 전 완료 task 일괄 처리.
- `9d306f5d`: task-mode workflow 노드 state 기반 resume.
- `6f66814e`: workflow LlmAgent 노드 strict input schema 검증.
- `1263ed64`: Workflow as Tool (`NodeTool`) — 노드를 격리 START→node Workflow로 실행.

Flows/Runner/Plugins/Contents:

- `7d0ae63a`: plugin `onAgentErrorCallback` / `onRunErrorCallback` (best-effort).
- `2aeb1e1b`: `RunConfig.modelInputContext` (LLM request transient context).
- `0c517e76`: compacted function call 복구.
- `49c0a365`: 컴팩션 이벤트를 runner가 yield (동기화 지점에서 append).
- `ad5445a1`: transfer 시 user input 유지.
- `81306bbb`: chat 경로 세션 1회 fetch (session config 유지).
- `6290aec5` (전부): litellm reasoning replay(구분자 미삽입) + **`RunConfig.includeThoughtsFromOtherAgents`** opt-in 플래그(다른 에이전트 thought를 `[agent] thought: ...` 컨텍스트로 변환).
- `78d1957a` / `e5fdb51e`: litellm signature-only 블록 보존 / streaming tool-call arg brace-depth 추적.

Server/Executors/도구/기타:

- `9a4f479d`: dev server DNS-rebinding 보호.
- `3f6eb1f0`: ApiServer 모드에서 내부 special agent(`__`) 차단 (`allowSpecialAgents`/`_guardSpecialAgentAccess`).
- `5b1088ac`: Cloud Run sandbox code executor.
- `b44d2c9d`: 컴팩션 요약 프롬프트/포맷 (앞선 섹션 참고).
- `fc985492` / `a680cea8`: ManagedAgent single_turn 래핑 (앞선 섹션 참고).
- transfer/request_input 프롬프트 parity (앞선 섹션 참고).
- `68a78030`: 비표준 `gen_ai.agent.workflow.steps` 메트릭 제거 (upstream이 표준 `gen_ai.invoke_agent.*`로 대체하며 삭제 — Dart도 동일 제거).
- `ac997706`: OAuth `prompt` 파라미터.
- `f9ffcfca`: A2A part 변환 시 빈 inline_data blob 스킵.
- 소규모 수정 다수 (`3c0fb65c`, `1509dcf3`, `53a8ab16` 등).

### ⏸ 보류 (Dart에 신규 서브시스템 필요 — 의식적으로 연기, 문서화)

- `50ff37f8` `to_mcp_server`: ADK 에이전트를 **MCP 서버로 노출**. Python은 `mcp.server.fastmcp.FastMCP` 기반이지만 Dart `adk_mcp`에는 **클라이언트 프리미티브만** 존재(서버 프레임워크 없음). 포팅하려면 stdio JSON-RPC MCP 서버(initialize/tools.list/tools.call/resource) 서브시스템을 먼저 구축해야 함.
- `07aa1e09` / `820a910e` / `5620d8f4` live 3종 (streaming tool yield / VAD 이벤트 반환 / non-blocking tool 백그라운드 태스크): Python `asyncio.create_task` + `asyncio.Lock` + `InvocationContext.active_non_blocking_tool_tasks` 레지스트리 + `BaseTool.response_scheduling`에 강결합. live/bidi 스트리밍 인프라 확장이 필요하고 기존 live 경로 회귀 위험이 있어, 별도 live 전용 작업 단위로 진행 권장.

### 🔎 잔여 백로그 (포팅 가능하나 이번 세션 미완 — 다음 작업 단위)

- `ecef5f85` / `c14258df`: BigQuery analytics plugin 필드 확장(tool 설명/파라미터 스키마 로깅, thinking/tool-use 토큰 컬럼). Dart `bigquery_agent_analytics_plugin.dart` 존재 — 포팅 가능. (위임 에이전트가 세션 한도로 중단, 미반영.)
- `ed579c13`: agent registry search agents/MCP servers. Dart `integrations/agent_registry/` 존재 — 포팅 가능. (동상.)

### ⛔ N/A (Dart에 대응 구조 없음 — 증거 기반 판정)

- `c2918211` (histogram 0 bucket): Dart 메트릭 레이어는 raw 샘플(`AdkMetricRecord`)만 기록하고 explicit bucket boundary/`_invoke_agent_*` 카운트 히스토그램을 정의하지 않음 → 조정 대상 없음.
- `8fc25f1e` (`cloud.resource_id`): Dart `getGcpResource()`에 agent-engine `cloud.resource.id` 분기가 없어 수정할 잘못된 키가 존재하지 않음.
- `20197de9` (`gen_ai.workflow.nested`): Dart telemetry에 `node_tracing`/`gen_ai.workflow.*` 노드 스팬 모듈 자체가 없음(OTel context 전파 서브시스템 부재).
- `41693dce` / `d831ee6e` / `3fa993bf` (mTLS): Dart에 google-auth mTLS workload-cert 전송 계층이 없음(GoogleApiToolset에 cert/mtls 표면 부재).
- `96d29143` (VertexAiRagMemoryService): Python은 `vertexai.preview.rag` SDK 최신화. Dart는 REST 기반 구현으로 SDK 메서드 시그니처 변경이 직접 매핑되지 않음(REST 엔드포인트 기준 재검토 필요 — 잔여).
- `ce2e4caf` (scheduler 수명주기), `a69ba4fa` (asyncio.shield): Dart Future는 취소 불가 → asyncio 구조 의존분 N/A.
- `ce2e4caf` DynamicNodeScheduler: Dart 미존재.

## 검증

- `dart test` 전체 통과: **1474 pass, 3 skipped, 0 fail** (baseline 1370 → wave1 1431 → wave2 1461 → wave3+마무리 1474).
- `flutter analyze` (example 앱) 이슈 없음.
- `dart analyze lib`: 신규 이슈 없음. 기존 `src/dev/web_server.dart`의 dart:mirrors 관련 33 error는 본 작업과 무관(VM에서 mirrors 미지원, 알려진 사항).
- 참고: 세션 한도로 wave-3 위임 에이전트(P5/P6) 2개가 중단되어, 잔여분은 upstream `57e1ba66` 대조로 커밋 단위 완료 여부를 직접 재검증 후 마무리함.
