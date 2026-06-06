# Phase2 Functional Runtime Validation (Part C / Part D)

- Date: 2026-02-28 11:14:52
- Scope (4-folder ownership x 2 workers)
  - Part C: `lib/src/dependencies`, `lib/src/models`, `lib/src/sessions`, related `test/*`
  - Part D: `lib/src/tools`, `lib/src/auth`, `lib/src/memory`, `lib/src/plugins`, related `test/*`

## 1) Python 기준 동작 계약 확인

참조 기준:
- `ref/adk-python/pyproject.toml`
- `ref/adk-python/src/google/adk/dependencies/rouge_scorer.py`
- `ref/adk-python/src/google/adk/dependencies/vertexai.py`
- `ref/adk-python/src/google/adk/models/interactions_utils.py`
- `ref/adk-python/src/google/adk/sessions/database_session_service.py`
- `ref/adk-python/src/google/adk/auth/*`, `plugins/*` (OAuth2/token/plugin callback 경계)

핵심 계약:
- Interactions 변환은 type별 엄격 payload 매핑(특히 function_result/result 문자열화, function_call 이름 유효성)
- Gemini REST transport는 헤더 병합/케이스 처리 + 비정상 JSON/SSE 에러를 명확히 표면화
- sqlite URL은 `sqlite://:memory:` 포함 실사용 URL 변형을 안정적으로 처리
- OAuth2 credential 흐름에서 `id_token` 보존 및 교환 실패 시 최소 credential 상태 보존
- Plugin callback 예외는 callback 문맥이 포함된 오류로 래핑

## 2) Dart 구현 검수 및 수정

주요 수정:
- `lib/src/models/interactions_utils.dart`
  - Python parity에 맞게 interaction content 변환 필드 정리
  - function_response result 문자열화 보강
  - 이름 없는 function_call output/delta 무시 처리
- `lib/src/models/gemini_rest_api_client.dart`
  - 커스텀 헤더 키를 소문자 정규화하여 `Accept` 케이스 충돌 방지
  - 비정상 JSON/SSE payload에 대한 명확한 예외 메시지 추가
- `lib/src/sessions/sqlite_session_service.dart`
  - `sqlite://:memory:` / `sqlite+aiosqlite://:memory:` shorthand 처리
  - sqlite 메모리 URL에서 파일 저장 대신 인메모리 백킹 유지
  - placeholder-style `%` 경로 처리 안정화
- `lib/src/auth/*`
  - OAuth2 parse/copy/exchange/refresh 전 경로에서 `id_token` 보존
  - `AuthHandler.parseAndStoreAuthResponse`에서 exchange 실패 전 초기 credential 저장
- `lib/src/plugins/plugin_manager.dart`
  - `runAfterRunCallback` 예외를 callback 명시 문맥으로 래핑
- 기존 변경 포함:
  - `lib/src/dependencies/dependency_container.dart`
  - `lib/src/dependencies/rouge_scorer.dart`
  - `lib/src/dependencies/vertexai.dart`
  - `lib/src/models/google_llm.dart`

## 3) 테스트 추가/수정

추가/수정 테스트:
- `test/interactions_utils_parity_test.dart` (신규)
- `test/gemini_rest_api_client_test.dart`
- `test/session_persistence_services_test.dart`
- `test/dependencies_parity_test.dart`
- `test/auth_handler_test.dart`
- `test/auth_preprocessor_test.dart`
- `test/credential_manager_test.dart`
- `test/plugin_manager_test.dart`

## 4) 의존성 호환성 조사 (Python -> Dart)

검토된 Dart 패키지:
- OAuth2 대응: `oauth2`
- Google auth 대응: `googleapis_auth`
- JWT/JOSE 대응: `jose`

판단:
- 이번 배치는 기존 주입형 exchange/refresh 구조에서 계약 불일치 수정만으로 해결 가능하여 신규 의존성 추가는 보류.
- 패키지 도입은 향후 "내장 OAuth2 full flow"가 필요할 때 단계적으로 적용.

## 5) 검증 결과

실행 커맨드:
- `dart format .` ✅
- `dart analyze` ✅ (error/warning 0, info 70)
- `dart test` ✅ (`674` passed, `~1` skipped)

## 6) 학습/운영 포인트

1. 런타임 회귀는 데이터 스키마보다 헤더/URL/토큰 보존 같은 경계 처리에서 자주 발생한다.
2. Interactions API는 필드 과다 전송보다 "정확한 최소 필드"가 호환성에 유리하다.
3. OAuth2 계열은 `id_token` 누락이 실제 인증 연동 장애로 직결된다.
4. callback 예외는 호출 지점 문맥이 포함되어야 운영 디버깅 속도가 높다.
