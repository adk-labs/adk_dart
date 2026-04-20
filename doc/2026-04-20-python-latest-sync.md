# 2026-04-20 adk-python latest sync

기준 upstream:
- `ref/adk-python`
- range: `fe48d875..e967f281`

이번 배치는 `adk-python` 최신 runtime diff에서 `adk_dart` 현재 구조에 직접 대응되는 항목만 반영했다. Python 내부 tracer context-manager 수정처럼 구현 기반이 다른 항목은 제외했고, 반대로 MCP 쪽은 upstream 커밋 로그를 다시 확인해 직접적인 런타임 누락이 보여 추가로 닫았다.

## 작업 단위 1. toolset auth credential 격리

작업 내용
- `InvocationContext`에 `credentialByKey` 저장소를 추가했다.
- `ReadonlyContext.getCredential()`를 추가했다.
- `BaseLlmFlow._resolveToolsetAuth()`가 shared `AuthConfig.exchangedAuthCredential`를 직접 mutate하지 않고 invocation-scoped credential 저장소에 결과를 넣도록 변경했다.
- pending auth request는 copy된 `AuthConfig` 기준으로 생성하도록 정리했다.

작업 이유
- upstream Python은 toolset auth 해석 결과를 context에 격리해서 race condition과 credential leakage를 막았다.
- 기존 Dart 구현은 shared toolset `AuthConfig`를 직접 mutate해서, 같은 toolset 인스턴스를 여러 invocation이 재사용하면 credential state가 섞일 수 있었다.
- `ReadonlyContext`에서 credential lookup이 가능해야 이후 toolset 구현이 invocation 단위 credential을 읽을 수 있다.

## 작업 단위 2. `LocalEnvironment` path-like 입력 허용

작업 내용
- `BaseEnvironment.readFile()` / `writeFile()` 시그니처를 `Object path` 기반으로 넓혔다.
- `LocalEnvironment`가 `String`, `Uri`, `FileSystemEntity`를 모두 path로 해석하도록 수정했다.
- 기존 working-directory 탈출 방어는 그대로 유지했다.

작업 이유
- upstream Python은 `str | Path` mismatch를 수정했다.
- 기존 Dart는 런타임 구현은 path-like 객체를 받아도 충분히 처리할 수 있었지만 시그니처가 `String`으로 좁아 public API parity가 맞지 않았다.
- 타입만 넓히고 보안 가드는 유지하는 것이 현재 Dart 구현에서 가장 안전한 대응이다.

## 작업 단위 3. `ApigeeLlm` refusal message parity

작업 내용
- chat-completions payload 생성 시 `[[REFUSAL]]: ...` 텍스트를 `content`와 `refusal` 필드로 분리하도록 수정했다.
- chat-completions response parser가 `message.refusal`을 다시 `[[REFUSAL]]: ...` marker가 붙은 텍스트 part로 복원하도록 맞췄다.

작업 이유
- upstream Python은 Apigee OpenAI-compatible 경로에서 refusal과 일반 content를 분리해서 직렬화/역직렬화하도록 바뀌었다.
- 기존 Dart는 refusal을 일반 텍스트로만 취급해서 최신 Python prompt/output semantics와 어긋날 수 있었다.

## 작업 단위 4. `SaveFilesAsArtifactsPlugin` file reference 옵션

작업 내용
- `SaveFilesAsArtifactsPlugin`에 `attachFileReference` 옵션을 추가했다.
- 옵션이 `false`면 artifact 저장과 placeholder 삽입은 유지하되 model-readable file reference part는 붙이지 않도록 변경했다.

작업 이유
- upstream Python은 artifact 저장만 하고 모델 접근용 file reference는 붙이지 않는 모드를 추가했다.
- Dart도 동일 옵션이 있어야 업스트림 샘플/설정과 맞는 동작을 선택할 수 있다.

## 작업 단위 5. `/run_live` `save_live_blob` query 반영

작업 내용
- dev web server `/run_live` websocket route가 `save_live_blob` query를 읽어서 `RunConfig.saveLiveBlob`에 반영하도록 수정했다.

작업 이유
- upstream Python은 `/run_live` endpoint에서 live blob persistence를 query 파라미터로 제어하도록 확장됐다.
- Dart 내부 runtime에는 이미 `saveLiveBlob` 경로가 있었지만, dev server route에서 query를 연결하지 않아 외부에서 켤 수 없는 상태였다.

## 작업 단위 6. MCP toolset credential wiring

작업 내용
- `McpToolset`에 optional `authConfig`를 추가했다.
- remote descriptor discovery 시 `ReadonlyContext.getCredential()` 결과를 auth header로 바꿔 `tools/list` 요청에 싣도록 수정했다.
- remote descriptor에서 materialize한 `McpTool`에도 동일 `authConfig` copy를 전달하도록 연결했다.

작업 이유
- upstream Python은 MCP toolset auth header를 invocation-scoped credential에서 읽도록 변경했다.
- 기존 Dart `McpToolset`은 `headerProvider`만 있었고 built-in auth wiring이 없어서, 이번에 추가한 `credentialByKey`가 실제 MCP discovery 경로에서는 사용되지 않았다.
- descriptor discovery 단계에서 인증이 필요한 MCP 서버를 다루려면 이 연결이 필요하다.

## 작업 단위 7. MCP tool error boundary 보강

작업 내용
- `McpTool.runAuthenticated()`가 local executor 예외와 remote JSON-RPC/transport 예외를 잡아서 `{'error': ...}` payload로 반환하도록 수정했다.

작업 이유
- upstream 최신 커밋은 MCP tool execution 오류가 runner 전체를 터뜨리지 않도록 경계를 추가했다.
- 기존 Dart는 MCP 예외가 그대로 bubble up해서 대화 흐름 자체가 중단될 수 있었다.
- 최소한 tool 호출 경계에서 structured error payload로 내리면 agent가 실패를 관찰하고 다음 턴을 계속 진행할 수 있다.

## 작업 단위 8. 회귀 테스트 보강

작업 내용
- `flow_processors_parity_test.dart`
  - toolset auth가 shared `AuthConfig`를 오염시키지 않고 invocation-scoped credential을 `getTools()`까지 전달하는지 검증 추가
- `environment_toolset_parity_test.dart`
  - `Uri` / `File` path 입력 허용 회귀 추가
- `models_parity_batch2_test.dart`
  - Apigee refusal payload/response roundtrip 회귀 추가
- `save_files_as_artifacts_plugin_test.dart`
  - `attachFileReference: false` 회귀 추가
- `dev_web_server_test.dart`
  - `/run_live?save_live_blob=true`가 `RunConfig.saveLiveBlob`로 전달되는지 검증 추가
- `mcp_resource_and_tool_test.dart`
  - invocation-scoped MCP descriptor auth header 회귀 추가
  - local executor/remote JSON-RPC MCP failure가 structured error payload로 내려오는지 검증 추가

작업 이유
- 이번 배치는 타입 변경보다 runtime 의미론 변경이 많아서, 단순 analyzer 통과만으로는 충분하지 않다.
- 특히 toolset auth, MCP, Apigee refusal은 실제로 “동작은 되지만 의미가 어긋나는” 종류의 regressions이어서 별도 회귀 테스트가 필요했다.

## 직접 포팅하지 않은 항목

- `BaseAgent` / `Runner` / `BaseLlmFlow`의 tracer context-manager detach 수정
  - Dart는 Python OpenTelemetry context manager를 직접 쓰지 않고 자체 in-memory tracer/telemetry 구조를 사용한다.
  - 동일한 cancellation-detach 버그 모델이 존재하지 않아 direct port 대상에서 제외했다.
- MCP bound token env patch
  - upstream patch는 Python process env와 Google auth stack의 bound token 공유 이슈를 우회하는 성격이다.
  - Dart runtime은 동일한 Python auth stack을 사용하지 않고 process env mutation도 같은 방식으로 다루지 않아서 direct port 대상에서 제외했다.

## 검증

- `dart format` 대상 파일 적용
- `dart analyze lib test`
  - error/warning 없음
  - 기존 info-level lint만 잔존
- 통과 테스트
  - `dart test test/flow_processors_parity_test.dart`
  - `dart test test/environment_toolset_parity_test.dart`
  - `dart test test/save_files_as_artifacts_plugin_test.dart`
  - `dart test test/models_parity_batch2_test.dart`
  - `dart test test/mcp_resource_and_tool_test.dart`
  - `dart test test/dev_web_server_test.dart --plain-name "maps save_live_blob query onto runLive RunConfig"`

메모
- macOS native asset(`.dart_tool/lib/libsqlite3.dylib`) 재작성 충돌 때문에 `dart test`는 병렬로 돌리지 않고 순차 실행으로 검증했다.
