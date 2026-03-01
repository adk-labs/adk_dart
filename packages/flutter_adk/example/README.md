# flutter_adk_example

`flutter_adk` 예제 앱입니다.

## 포함 예제
- `Basic Chatbot`: 단일 `Agent + FunctionTool` 예제
- `Multi-Agent`: 공식 문서 MAS의 Coordinator/Dispatcher 패턴 예제
  - `HelpDeskCoordinator`가 `Billing`, `Support` sub-agent로 라우팅
- `Workflow`: `SequentialAgent + ParallelAgent + LoopAgent` 조합 예제

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
2. 상단 세그먼트에서 예제를 선택
3. 메시지를 보내 동작 확인

멀티에이전트 테스트 예시:
- `결제가 두 번 청구됐어요` (Billing 라우팅)
- `로그인이 안 되고 앱에서 오류가 나요` (Support 라우팅)

워크플로우 테스트 예시:
- `파리 2박 3일 일정 추천`
- `신규 구독 플랜 UX 개선 아이디어`

## 주의사항
- 브라우저에 API 키를 저장하는 방식은 노출 위험이 있으므로 프로덕션에서는 서버 프록시를 권장합니다.
- 로컬 개발에서 최신 루트 소스를 참조하기 위해 `pubspec_overrides.yaml`이 포함되어 있습니다.
