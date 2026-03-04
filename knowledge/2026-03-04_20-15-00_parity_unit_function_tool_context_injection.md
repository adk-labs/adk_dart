# Parity Unit: FunctionTool Context Injection Names (Python 2026-03-03 반영)

- Date: 2026-03-04
- Scope:
  - `lib/src/tools/function_tool.dart`
  - `test/tools_parity_test.dart`
- Reference upstream change:
  - `90f28dee` (ToolContext 주입 커스텀 파라미터명 허용)

## 구현 내용

1. FunctionTool 생성자 확장
- `toolContextParamNames` 옵션 추가.
- 기본값으로 기존 `toolContext`를 항상 포함해 backward compatibility 유지.
- 공백/중복 제거 정규화 로직 추가.

2. 호출 플랜 확장
- 기존 고정 `#toolContext` named injection 외에,
  등록된 커스텀 이름(Symbol)들로 named injection 시도.
- 기존 fallback 호출 순서(plain named/positional/args-only)는 유지.

3. 회귀 방지 테스트 추가
- `tools_parity_test.dart`에 커스텀 이름(`ctx`) 파라미터로 `ToolContext`를 주입하는 케이스 추가.

## 검증

- Added tests:
  - `test/tools_parity_test.dart` custom context param name test

- Executed:
  - `dart analyze` (changed files)
  - `dart test test/a2a_parity_test.dart test/tools_parity_test.dart test/code_execution_parity_test.dart test/dev_web_server_test.dart`

## 결과

- 기존 `toolContext` 시그니처 호환 유지.
- Python 변경사항과 맞춰 커스텀 ToolContext 파라미터명 사용 가능.

