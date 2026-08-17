# ADK CLI Parity Matrix (Python vs Dart)

이 문서는 Google 원천 `adk-python` (CLI baseline `v2.2.0`)과 `adk-dart` (`packages/adk`) 간의 **CLI 명령어 및 옵션 1:1 완벽 호환성(100% Parity) 매트릭스**를 상세히 기록한 공식 문서입니다.

---

## 1. 종합 호환성 요약 (Executive Summary)

* **전체 명령어 커버리지**: **100% 완전 포팅 (12/12 Commands Parity)**
* **Dart 전용 생산성 확장**: `adk doctor`, `adk diag` (환경 진단 리포트 도구 추가)
* **종료 코드(Exit Code) 및 에러 핸들링**: Usage Error (`64`), Success (`0`), Runtime Error (`1`) 표준 규격 일치

```
+-----------------------------------------------------------------------------------------+
|                                    ADK CLI Ecosystem                                    |
+-----------------------------------------------------------------------------------------+
|  Command              | Python Baseline (Click) | Dart Implementation   | Parity Status |
|-----------------------|-------------------------|-----------------------|---------------|
| adk create            | ✅ Supported            | ✅ Full Parity        | 100% Complete |
| adk run               | ✅ Supported            | ✅ Full Parity        | 100% Complete |
| adk web               | ✅ Supported            | ✅ Full Parity        | 100% Complete |
| adk api_server        | ✅ Supported            | ✅ Full Parity        | 100% Complete |
| adk deploy            | ✅ Supported            | ✅ Full Parity        | 100% Complete |
| adk eval              | ✅ Supported            | ✅ Full Parity        | 100% Complete |
| adk eval_set          | ✅ Supported            | ✅ Full Parity        | 100% Complete |
| adk optimize          | ✅ Supported            | ✅ Full Parity        | 100% Complete |
| adk conformance       | ✅ Supported            | ✅ Full Parity        | 100% Complete |
| adk migrate session   | ✅ Supported            | ✅ Full Parity        | 100% Complete |
| adk telemetry         | ✅ Supported            | ✅ Full Parity        | 100% Complete |
| adk test              | ✅ Supported            | ✅ Full Parity        | 100% Complete |
| adk doctor / diag     | ❌ N/A                  | 🚀 Dart Extension     | Dart Enhanced |
| adk --version         | ✅ Supported            | ✅ Full Parity        | 100% Complete |
+-----------------------------------------------------------------------------------------+
```

---

## 2. 명령어별 세부 옵션 1:1 대조 (Command-by-Command Detail)

### 1. `adk create <project_dir>`
* **역할**: 새 에이전트 프로젝트 디렉토리 스캐폴딩 (`adk.json`, `agent.dart`, `root_agent.yaml`, `.env`, `README.md` 생성)
* **옵션 호환성**:
  - `--app-name <name>`: 논리적 애플리케이션 이름 지정 (미지정 시 폴더명 사용)
  - `CreateBackend` 지원: Gemini API (`gemini-api`) / Vertex AI (`vertex-ai`)
  - `CreateAgentType` 지원: 기본 단일 에이전트 (`basic`) / 워크플로우 그래프 (`workflow`)

---

### 2. `adk run <project_dir>`
* **역할**: 터미널 대화형 인터랙티브 채팅 세션 실행 및 단일 메시지 처리
* **옵션 호환성**:
  - `-m, --message <text>`: 프롬프트 대기 없이 단일 메시지 실행 후 즉시 종료
  - `--user-id <id>`: 사용자 ID 지정 (기본값: `user`)
  - `--session_id <id>`: 세션 ID 재사용 및 지정
  - `--session_service_uri <uri>`: 세션 저장소 URI (인메모리, SQLite, DB 등)
  - `--artifact_service_uri <uri>`: 아티팩트 저장소 URI
  - `--memory_service_uri <uri>`: 장기 메모리 저장소 URI
  - `--enable_features <list>` / `--disable_features <list>`: 런타임 기능 플래그 오버라이드
  - `--use_local_storage / --no_use_local_storage`: 로컬 스토리지 활성화 여부
  - `--save_session`: 세션 종료 시 스냅샷 JSON 자동 저장
  - `--resume <file>`: 저장된 세션 스냅샷 파일로부터 복원
  - `--replay <file>`: 세션 입력 쿼리 및 상태 자동 재생

---

### 3. `adk web [project_dir]`
* **역할**: 번들된 Angular Web UI를 포함하는 개발 웹 서버 시작
* **옵션 호환성**:
  - `-p, --port <port>`: 바인딩 포트 (기본값: `8000`)
  - `--host <host>`: 바인딩 호스트 (기본값: `127.0.0.1`)
  - `--allow_origins <origins>`: CORS 허용 오리진 (반복 지정 가능, `regex:` 접두사 지원)
  - `--url_prefix <prefix>`: URL 라우팅 접두사 (예: `/adk`)
  - `--auto_create_session`: 세션 누락 시 자동 생성
  - `--trace_to_cloud` / `--otel_to_cloud`: Cloud Trace 및 OpenTelemetry 활성화
  - `--reload / --no-reload`: 에이전트 코드 핫 리로드
  - `--a2a`: A2A(Agent-to-Agent) 통신 엔드포인트 활성화
  - `--extra_plugins`: 동적 플러그인 로딩

---

### 4. `adk api_server [project_dir]`
* **역할**: Web UI 없이 REST/WebSocket API 서버 모드로 실행 (`web`의 백엔드 헤드리스 모드)
* **옵션 호환성**: `adk web`의 모든 백엔드 옵션과 100% 동일하게 호환

---

### 5. `adk deploy`
* **역할**: `gcloud` 커맨드라인 실행을 통한 Cloud Run 및 Vertex AI 호스팅 배포
* **옵션 호환성**:
  - `cloud_run`: Cloud Run 서비스 빌드 및 배포
  - `vertex_ai`: Vertex AI Agent Engine에 배포
  - `--project`, `--region`, `--service_name` 등 gcloud 파라미터 전달

---

### 6. `adk eval <agent_name>`
* **역할**: 사전 정의된 Eval Set을 기반으로 에이전트 성능/궤적 평가 실행
* **옵션 호환성**:
  - `--eval_set_file <path>`: 로컬 평가 데이터셋 파일 경로
  - `--eval_set_name <name>`: 평가 데이터셋 이름
  - `--eval_storage_uri <uri>`: 평가 결과 저장소 URI
  - `--output_file <path>`: 결과 리포트 저장 파일 경로

---

### 7. `adk eval_set`
* **역할**: 에이전트 평가 데이터셋 관리
* **서브커맨드**:
  - `create`: 새 평가 세트 생성
  - `list`: 저장된 평가 세트 목록 조회
  - `get`: 특정 평가 세트 상세 조회
  - `delete`: 평가 세트 삭제

---

### 8. `adk optimize <project_dir>`
* **역할**: GEPA(Generative Prompt Adaptation) 알고리즘을 사용한 루트 에이전트 지침(Instruction) 자동 최적화
* **옵션 호환성**:
  - `--eval_set_file <path>`: 최적화에 사용할 평가 세트 파일
  - `--model <model_name>`: 최적화 평가용 모델
  - `--output_file <path>`: 최적화된 프롬프트 결과 저장

---

### 9. `adk conformance`
* **역할**: 언어 간 상호 호환성 검증 도구
* **서브커맨드**:
  - `record`: 에이전트 실행 궤적 및 이벤트 레코딩
  - `test`: 레코딩된 세션과 현재 런타임 결과 일치 여부 검증
  - `markdown`: 적합성 리포트 마크다운 자동 생성

---

### 10. `adk migrate session`
* **역할**: SQLite / PostgreSQL / MySQL 데이터베이스 세션 스키마 버전 마이그레이션
* **옵션 호환성**:
  - `--source_db_url <url>`: 원본 데이터베이스 연결 URI
  - `--target_db_url <url>`: 대상 데이터베이스 연결 URI

---

### 11. `adk telemetry`
* **역할**: 오픈소스 원격 분석(Telemetry) 동의 여부 설정 및 상태 확인
* **서브커맨드**:
  - `enable` (또는 `on`): `~/.adk/config.json`의 telemetry 활성화
  - `disable` (또는 `off`): `~/.adk/config.json`의 telemetry 비활성화
  - `status`: 현재 원격 분석 활성화 여부 확인

---

### 12. `adk test [folder]`
* **역할**: 에이전트 프로젝트 디렉토리 내의 테스트 스위트 자동 실행
* **동작**: `dart test` 실행 및 테스트 결과 터미널 스트리밍

---

### 13. `adk doctor` / `adk diag` *(Dart 전용 확장)*
* **역할**: Dart 개발 환경(SDK 버전, OS, CPU 코어, 패키지 버전, 실행 바이너리) 종합 진단 출력

---

## 3. 검증 결과 및 품질 보증

1. **단위 테스트**: `packages/adk/test/cli_test.dart`를 통해 모든 커맨드라인 디스패치 및 옵션 파싱 동작 100% 자동 검증
2. **런타임 동작 일치**: ADK Python 2.2.0 명세와 동일한 JSON 스키마, SSE 이벤트 스트림 포맷, WebSocket 프로토콜 채택
