# flutter_adk_example

`flutter_adk` 예제 앱입니다.

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

## 주의사항
- 브라우저에 API 키를 저장하는 방식은 노출 위험이 있으므로 프로덕션에서는 서버 프록시를 권장합니다.
- 로컬 개발에서 최신 루트 소스를 참조하기 위해 `pubspec_overrides.yaml`이 포함되어 있습니다.
