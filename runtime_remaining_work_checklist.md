# ADK Dart 실제 동작 남은 작업 체크리스트 (재전수검사)

기준일: 2026-02-28  
검토 기준: "기본 사용 시 실제 기능이 동작하는가?"  
판정 방식: 문서/옵션 존재와 무관하게 런타임에서 실제 처리 불가면 미완료로 분류.

---

## P0 (즉시 동작 불가 / 사용자 체감 치명)

| 체크 | 항목 | 현재 상태 (근거) | 완료 기준 |
| --- | --- | --- | --- |
| [ ] | `gs://` 아티팩트 서비스 기본 경로 동작 불가 | 서비스 레지스트리는 `GcsArtifactService(parsed.authority)`를 반환하지만(`lib/src/cli/service_registry.dart:192`), 해당 생성자는 live 모드에서 `httpRequestProvider/authHeadersProvider` 없으면 즉시 예외(`lib/src/artifacts/gcs_artifact_service.dart:64`) | `artifact_service_uri=gs://...`만으로 실제 읽기/쓰기 가능 |
| [ ] | `postgresql://`, `mysql://` 세션 URI가 등록되어 있으나 실구현 미연결 | 레지스트리는 두 스킴을 `DatabaseSessionService`로 연결(`lib/src/cli/service_registry.dart:172`), 그러나 `DatabaseSessionService`는 기본적으로 sqlite/memory 외 `UnsupportedError`(`lib/src/sessions/database_session_service.dart:80`) | Postgres/MySQL 기본 어댑터 제공 또는 등록 제거/명시적 fail-fast |
| [ ] | BigQuery 기본 클라이언트 부재 | 기본 팩토리가 즉시 `StateError`(`lib/src/tools/bigquery/client.dart:146`) | `BigQueryToolset`가 별도 팩토리 주입 없이 기본 호출 가능 |
| [ ] | Bigtable 기본 클라이언트 부재 | admin/data 팩토리 미설정 시 즉시 예외(`lib/src/tools/bigtable/client.dart:102`, `lib/src/tools/bigtable/client.dart:116`) | `BigtableToolset` 기본 호출 가능 |
| [ ] | Spanner 기본 클라이언트 부재 + 임베딩 런타임 부재 | 기본 클라이언트 예외(`lib/src/tools/spanner/client.dart:100`), 임베더 미설정 예외(`lib/src/tools/spanner/utils.dart:171`) | Spanner 툴/벡터 검색이 기본 설정에서 동작 |
| [ ] | BigQuery Data Insights 기본 스트림 제공자 부재 | 기본 제공자가 즉시 `StateError`(`lib/src/tools/bigquery/data_insights_tool.dart:402`) | `ask_data_insights` 기본 동작 |
| [ ] | `VertexAiSessionService`가 실제 원격 저장소가 아닌 in-memory delegate 사용 | 내부 delegate가 `InMemorySessionService`(`lib/src/sessions/vertex_ai_session_service.dart:21`) | Vertex AI/Agent Engine 세션 영속 경로 실제 구현 |
| [ ] | 원격 코드 실행기 기본 경로 부재(로컬 fallback 의존) | GKE local fallback(`lib/src/code_executors/gke_code_executor.dart:149`), AgentEngine sandbox local fallback(`lib/src/code_executors/agent_engine_sandbox_code_executor.dart:114`), Vertex client 미설정 시 예외(`lib/src/code_executors/vertex_ai_code_executor.dart:154`) | 클라이언트 미주입 시에도 원격 실행 기본 경로 제공 또는 명시적 fail-fast 정책 확정 |
| [ ] | 일부 모델 커넥터가 실제 API 호출 대신 synthetic 응답으로 폴백 | Anthropic(`lib/src/models/anthropic_llm.dart:225`), LiteLLM(`lib/src/models/lite_llm.dart:177`), Apigee chat completions(`lib/src/models/apigee_llm.dart:143`) | 기본 transport/invoker 연결로 실제 API 호출 수행 |

---

## P1 (핵심 기능 범위/패리티 부족)

| 체크 | 항목 | 현재 상태 (근거) | 완료 기준 |
| --- | --- | --- | --- |
| [ ] | `adk web` Python 대비 엔드포인트/스트리밍 세부 패리티 | 남은 갭이 별도 문서에 정리됨(`web_parity_status.md:53`) | Eval/Debug/Trace/streaming 상세까지 Python과 동등 |
| [ ] | `adk web` 파싱만 하고 미구현인 옵션 실동작 | CLI가 "옵션 수용 but 미완전" 명시(`lib/src/dev/cli.dart:771`) | `trace_to_cloud`, `otel_to_cloud`, `reload_agents`, `a2a`, `extra_plugins`, `reload` 실제 구현 |
| [ ] | `deploy` 명령이 실제 배포 수행 안 함 (프리뷰 출력만) | `deploy`에서 gcloud 커맨드 문자열만 출력(`lib/src/cli/cli_tools_click.dart:38`) + deploy 모듈은 인자 조합 함수만 존재(`lib/src/cli/cli_deploy.dart:40`) | 실제 배포 실행/검증/에러 처리 제공 |
| [ ] | `adk_dart` MCP 툴셋은 Streamable HTTP만 직접 지원 | Toolset connection이 `StreamableHTTPConnectionParams` 고정(`lib/src/tools/mcp_tool/mcp_toolset.dart:18`), 반면 `adk_mcp`에는 stdio 클라이언트 존재(`packages/adk_mcp/lib/src/mcp_stdio_client.dart:48`) | `McpToolset` 레벨에서 stdio 연결 경로 제공 |
| [ ] | Google API Toolset 기본 discovery spec fetcher 부재 | spec/discovery 주입 없으면 즉시 예외(`lib/src/tools/google_api_tool/googleapi_to_openapi_converter.dart:37`) | 기본 fetcher 제공 또는 사전 번들 스펙 제공 |
| [ ] | Toolbox Toolset 기본 delegate 부재 | delegate 미주입 시 즉시 예외(`lib/src/tools/toolbox_toolset.dart:18`) | 기본 toolbox SDK adapter 제공 |
| [ ] | Discovery Engine 검색 기본 handler 부재 | handler 없으면 error payload 반환(`lib/src/tools/discovery_engine_search_tool.dart:118`) | 기본 검색 실행기 제공 |
| [ ] | Audio 전사 기본 recognizer 부재 | recognizer 없으면 즉시 예외(`lib/src/flows/llm_flows/audio_transcriber.dart:79`) | 기본 STT 연결 또는 명시적 선택형 모듈 제공 |
| [ ] | Secret Manager 기본 fetcher 부재 | 기본 fetcher가 즉시 예외(`lib/src/tools/apihub_tool/clients/secret_client.dart:61`) | Secret Manager 기본 클라이언트 제공 |
| [ ] | OpenAPI parser 외부 `$ref` 미지원 | external ref에서 즉시 예외(`lib/src/tools/openapi_tool/openapi_spec_parser/openapi_spec_parser.dart:341`) | multi-file OpenAPI `$ref` 로딩 지원 |
| [ ] | Spanner PostgreSQL dialect 기능 제한 | query/metadata에서 unsupported 처리(`lib/src/tools/spanner/utils.dart:32`, `lib/src/tools/spanner/metadata_tool.dart:112`), ANN은 명시적 미지원(`lib/src/tools/spanner/search_tool.dart:193`) | PostgreSQL dialect 핵심 read/search/metadata 경로 지원 |

---

## P2 (운영 안정화/품질 보강)

| 체크 | 항목 | 현재 상태 (근거) | 완료 기준 |
| --- | --- | --- | --- |
| [ ] | SQLite 배포 환경 호환성 매트릭스 확정 | 플랫폼별 동적 라이브러리 직접 로딩(`lib/src/sessions/sqlite_session_service.dart:1753`) | OS/컨테이너별 런타임 가이드 + CI 검증 |
| [ ] | 클라우드 경로 E2E 테스트 보강 | 현재는 로컬/모의 중심 테스트 편중 | `gs://`, `postgresql://`, `mysql://`, BigQuery/Bigtable/Spanner, 원격 코드실행기 실환경 smoke 추가 |
| [ ] | fallback 차단 모드(`strict runtime`) 도입 | 일부 기능이 로컬 fallback으로 조용히 전환됨 | 운영 모드에서 fallback 발생 시 즉시 실패/진단 |
| [ ] | 사용 가이드 보강 | 기능별 "무엇을 주입해야 동작하는지" 분산 | README/패키지 문서에 runtime preflight + 필수 의존성 체크리스트 정리 |

---

## 재검사 메모 (이번에 확인한 변경점)

- [x] `adk_mcp` 자체는 stdio 클라이언트와 server-request 응답 루프가 이미 구현되어 있음.
- [ ] 다만 `adk_dart`의 MCP Toolset 통합은 아직 Streamable HTTP 중심이라 stdio 사용 경로가 사용자 레벨에 노출되지 않음.
