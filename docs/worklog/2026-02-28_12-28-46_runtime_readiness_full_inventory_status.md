# Runtime Readiness Full Inventory Status (2026-02-28 12:28)

## 목적
- `adk_dart/lib/src` 전체 28개 폴더를 전수조사해, "1:1 포팅"에서 "실동작 검증" 단계로 전환 시 현재 진행률과 리스크를 정리한다.

## 조사 방법
- 폴더 4개 단위로 7개 배치로 분할 조사.
- 각 배치는 다음을 점검:
  - Placeholder 흔적(`TODO`, `FIXME`, `UnimplementedError`, stub-like throw/no-op)
  - 외부 연동 지점 및 런타임 가드
  - 테스트 존재 여부
  - 실동작 검증 관점의 gap
- 본 문서는 정적 코드/테스트 자산 기반 인벤토리다. 실환경 자격증명 기반 E2E 실행은 별도 단계로 남아 있다.

## 전체 진행률
- 대상 폴더: 28
- `Ready`: 7 (25.0%)
- `Partial`: 14 (50.0%)
- `Risky`: 7 (25.0%)
- 단순 가중 진행률(Ready=1, Partial=0.5, Risky=0): 50.0%

## 폴더별 상태
| 폴더 | 상태 |
|---|---|
| `a2a` | Partial |
| `agents` | Partial |
| `apps` | Ready |
| `artifacts` | Risky |
| `auth` | Partial |
| `cli` | Partial |
| `code_executors` | Risky |
| `dependencies` | Partial |
| `dev` | Partial |
| `errors` | Ready |
| `evaluation` | Risky |
| `events` | Ready |
| `examples` | Ready |
| `features` | Ready |
| `flows` | Partial |
| `memory` | Risky |
| `models` | Partial |
| `optimization` | Partial |
| `planners` | Partial |
| `platform` | Risky |
| `plugins` | Partial |
| `runners` | Ready |
| `sessions` | Risky |
| `skills` | Partial |
| `telemetry` | Partial |
| `tools` | Risky |
| `types` | Ready |
| `utils` | Partial |

## Placeholder/미구현 흔적 요약
- `lib/src` 기준 `TODO/FIXME/UnimplementedError`는 사실상 0건(실행 코드 기준).
- 예외:
  - `lib/src/cli/built_in_agents/instruction_embedded.template`의 TODO 문구(템플릿 텍스트)
  - `lib/src/cli/built_in_agents/tools/write_config_files.py`의 TODO 주석
- 실질 리스크는 "명시적 TODO"보다 "fallback/no-op/in-memory substitute" 형태로 존재.

## 핵심 리스크 10개 (실동작 우선순위)
1. `tools`: 외부 연동면이 매우 넓고(client factory 주입 의존), 미구성 시 런타임 예외 다수.
2. `sessions`: `SqliteSessionService`가 실제 SQLite 엔진이 아닌 JSON 파일 기반 동작, `VertexAiSessionService`는 in-memory 위임.
3. `code_executors`: Docker/GKE/Agent Engine/Vertex/Python 의존 경로가 fallback 중심.
4. `evaluation`: `fake_gcs`, 로컬 Vertex 점수 fallback, no-op 출력 경로 존재.
5. `memory`: Vertex 메모리 경로가 네트워크/인증 의존 + in-memory fallback 기본값.
6. `artifacts`: `GcsArtifactService`가 실제 GCS backend가 아닌 in-memory 구현.
7. `models`: Anthropic/Apigee/LiteLLM 경로에서 미주입 시 synthetic fallback 응답 가능.
8. `platform`: `AdkThread`가 isolate/thread가 아닌 `Future` 래퍼 수준.
9. `plugins`: callback safe wrapper에서 오류 삼킴(`catch (_)`)로 운영 관측성 저하.
10. `cli`: deploy가 preview 중심이며 실제 실행 경로 고도화 필요.

## Python 계약 대비 주의 포인트
- Python ADK의 "클라우드/서비스 실연동" 기대치 대비 Dart 쪽은 다수 컴포넌트가 현재 fallback 또는 주입 전제 구조다.
- 특히 다음 영역은 "계약은 존재하나 실연동 미확정" 상태:
  - Artifact GCS
  - Session Vertex/DB 실백엔드
  - Executor GKE/AgentEngine/Vertex
  - Evaluation Vertex/GCS
  - 일부 모델 provider 경로

## 테스트 자산 상태
- 테스트 파일 수가 많아 표면계약/파리티 검증은 풍부함.
- 다만 다수는 mock/in-memory/parity 성격이며, secret-gated 실서비스 통합 테스트 lane은 상대적으로 약함.
- 다음 폴더는 테스트 대비 실연동 검증 공백이 큼:
  - `tools`, `code_executors`, `sessions`, `evaluation`, `memory`, `artifacts`

## 즉시 실행 권장 백로그 (P0/P1)
### P0 (실동작 차단 해소)
1. `sessions`: SQLite 실엔진 기반 구현 또는 명시적 파일DB 서비스 분리/명명 정정.
2. `artifacts`: GCS 실백엔드 구현(또는 in-memory fallback 명시 분리 + 강제 설정 체크).
3. `code_executors`: 주입 누락 시 synthetic/fallback 대신 fail-fast + preflight 진단.
4. `tools`: client factory/provider 미설정 사전검증(preflight) 추가.

### P1 (운영 품질 강화)
1. `evaluation`/`memory`: fallback 경로와 live 경로를 테스트 매트릭스로 분리하고 credentialed smoke lane 추가.
2. `plugins`: 예외 삼킴 제거 또는 구조화 로그/telemetry 이벤트로 승격.
3. `models`: provider별 fallback 응답 정책 정리(명시 실패 vs 테스트 대역 응답).
4. `cli`: deploy 실실행 모드 분리(`--dry-run` vs `--apply`)와 검증 추가.

## 권장 실행 순서 (Phase2 다음 배치)
1. Batch F: `sessions` + `artifacts`
2. Batch G: `code_executors` + `tools` preflight
3. Batch H: `evaluation` + `memory` live-lane
4. Batch I: `models` + `plugins` 운영 안정화
5. Batch J: `cli` deploy + `platform` 계약 정리

## 학습/공유 포인트
- "TODO가 없는 것"과 "실동작 준비 완료"는 다르다.
- 현재 병목은 문법 미완성보다 외부연동 구성과 fallback 정책 일관성에 있다.
- 다음 단계의 성공 기준은 기능 구현량이 아니라 "실서비스 환경에서의 fail-fast + 관측성 + 재현 가능한 통합 테스트"다.
