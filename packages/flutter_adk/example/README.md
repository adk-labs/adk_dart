# flutter_adk_example

`flutter_adk` 예제 앱입니다.

## 다국어 지원
- 지원 언어: English, 한국어, 日本語, 中文
- 상단 `번역(🌐)` 아이콘에서 즉시 전환할 수 있습니다.
- 선택 언어는 로컬 저장소에 유지됩니다.

## 포함 예제
- `Basic Chatbot`: 단일 `Agent + FunctionTool` 예제
- `Transfer Multi-Agent`: 공식 문서 MAS의 Coordinator/Dispatcher 패턴 예제
  - `HelpDeskCoordinator`가 `Billing`, `Support` sub-agent로 라우팅
- `Workflow Combo`: `SequentialAgent + ParallelAgent + LoopAgent` 조합 예제
- `Sequential`: 코드 작성 -> 리뷰 -> 리팩터링 순차 실행 예제
- `Parallel`: 독립 관점 에이전트 병렬 실행 + 통합 예제
- `Loop`: Critic/Refiner 반복 개선 + `exit_loop` 종료 예제
- `Agent Team`: Coordinator가 Greeting/Weather/Farewell 팀으로 transfer 라우팅
- `MCP Toolset`: `McpToolset + StreamableHTTPConnectionParams` 기반 원격 MCP 예제
- `Skills`: inline `Skill + SkillToolset` 기반 스킬 오케스트레이션 예제

## 실행

```bash
flutter pub get
flutter run
```

웹 빌드:

```bash
flutter build web
```

## 사용 방법
1. 앱 우측 상단 설정에서 Gemini API 키를 입력/저장
2. (MCP 예제 사용 시) MCP Streamable HTTP URL(+ 선택: Bearer Token) 입력
3. 상단 칩(ChoiceChip)에서 예제를 선택
4. 메시지를 보내 동작 확인

Transfer 멀티에이전트 테스트 예시:
- `결제가 두 번 청구됐어요` (Billing 라우팅)
- `로그인이 안 되고 앱에서 오류가 나요` (Support 라우팅)

Workflow Combo 테스트 예시:
- `파리 2박 3일 일정 추천`
- `신규 구독 플랜 UX 개선 아이디어`

Sequential 테스트 예시:
- `숫자 리스트의 최댓값을 구하는 파이썬 함수를 작성해줘`

Parallel 테스트 예시:
- `신규 B2B 요금제 출시 전략을 제안해줘`

Loop 테스트 예시:
- `고양이가 모험을 떠나는 짧은 동화 써줘`

Agent Team 테스트 예시:
- `안녕`
- `서울 시간 알려줘`
- `뉴욕 날씨 어때?`
- `고마워, 잘가`

MCP Toolset 테스트 예시:
- `MCP 연결 상태 확인해줘`
- `MCP 서버에 있는 tool 목록으로 가능한 작업을 알려줘`

Skills 테스트 예시:
- `이 공지문 문장을 더 간결하게 다듬어줘`
- `신규 기능 출시 계획을 단계별로 정리해줘`

## 사용자 정의 예제(User Example)
- 홈 우하단 `New Example` 버튼으로 사용자 예제를 만들 수 있습니다.
- 한 예제 안에서 에이전트를 여러 개 구성하고, 연결 방식(Topology)을 고를 수 있습니다.
  - `Single Agent`
  - `Agent Team`
  - `Sequential Workflow`
  - `Parallel Workflow`
  - `Loop Workflow`
- 생성한 예제는 로컬에 저장되어 앱 재실행 후에도 그대로 재사용됩니다.

### 그래프 연결 규칙 DSL
사용자 예제의 Connection 조건은 아래 DSL을 지원합니다.

- `always`
  - 무조건 해당 edge를 우선 적용
- `intent:<name>`
  - 의도(intent)가 `<name>`일 때 라우팅
  - 예: `intent:weather`, `intent:billing`, `intent:login`
- `contains:<keyword>`
  - 사용자 메시지에 `<keyword>`가 포함되면 라우팅(대소문자 무시)
  - 예: `contains:refund`, `contains:서울`

예시:
- `A0 -> A1` 조건: `intent:weather`
- `A0 -> A2` 조건: `contains:refund`
- `A0 -> A3` 조건: `always` (기본 fallback)

권장:
- Team 토폴로지에서는 시작 에이전트(Entry Agent)를 먼저 지정하고, Entry 기준 라우팅 규칙을 연결하세요.
- Sequential/Parallel/Loop 토폴로지에서는 연결 그래프가 실행 우선순위(노드 순서)에 반영됩니다.

## 주의사항
- 브라우저에 API 키를 저장하는 방식은 노출 위험이 있으므로 프로덕션에서는 서버 프록시를 권장합니다.
- 로컬 개발에서 최신 루트 소스를 참조하기 위해 `pubspec_overrides.yaml`이 포함되어 있습니다.
