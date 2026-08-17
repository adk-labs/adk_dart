# Agent Development Kit (ADK) for Dart

[English](README.md) | 한국어 | [日本語](README.ja.md) | [中文](README.zh.md)

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![pub package](https://img.shields.io/pub/v/adk_dart.svg)](https://pub.dev/packages/adk_dart)
[![Package Sync](https://github.com/adk-labs/adk_dart/actions/workflows/package-sync.yml/badge.svg)](https://github.com/adk-labs/adk_dart/actions/workflows/package-sync.yml)

ADK Dart는 모듈형 런타임 프리미티브, 도구 오케스트레이션 및 MCP(Model Context Protocol) 연동을 제공하는 자율 AI 에이전트 구축 및 런타임 실행을 위한 오픈소스, 코드 중심(Code-First) Dart 엔지니어링 프레임워크입니다.

실질적인 런타임 호환성, 비동기 파이프라인 무결성 및 개발자 경험(DX)과 직관적인 API 사용성에 중점을 둔 Google ADK 아키텍처의 Dart 네이티브 포트입니다.

---

## 최신 업데이트

- **ADK 2.0 워크플로우 및 Managed Agent 지원**: 핵심 ADK 2.0 아키텍처 완벽 지원:
  - **v2 워크플로우**: `Workflow`, `BaseNode`, `JoinNode` 등을 활용한 선언적 DAG 노드 그래프 스케줄링, 의존성 관리, 조건부 분기 라우팅 및 상태 병합 지원.
  - **Managed Agents**: `ManagedAgent` 및 `RemoteMcpServer` 설정을 통한 GCP Vertex AI Managed Agents Interactions API 직접 RPC 연동 지원.
- **MCP 프로토콜 코어 패키지 분리**: `packages/adk_mcp` 패키지를 추가하고 Streamable HTTP MCP 전송 계층을 독립 패키지로 모듈화.
- **MCP 스펙 고도화**: 세션 복구, 요청 ID 기반 SSE 응답 매칭, 취소 알림 인터럽트, 기능(Capability) 기반 RPC 사용 등 MCP 생명주기 및 전송 안정성 강화.
- **호환성 확장**: 세션 영속 스토리지, 툴셋 리플렉션, 모델/도구 통합 계층 전반에 걸친 광범위한 런타임 호환성 확보.

## 핵심 기능

- **코드 중심 에이전트 런타임**: `BaseAgent`, `LlmAgent`(`Agent` 별칭) 및 명시적 인보케이션/세션 컨텍스트 객체를 사용한 에이전트 구축.
- **이벤트 기반 실행 파이프라인**: `Runner` / `InMemoryRunner`를 통한 비동기 에이전트 실행 및 `Event` 스트림 디스패치.
- **계층형 멀티 에이전트 오케스트레이션**: `subAgents`를 사용한 계층적 에이전트 트리 구성 및 자율 Hand-off 상태 전이.
- **풍부한 도구 생태계**: `FunctionTool`, OpenAPI 도구, Google API 툴셋, 엔터프라이즈 데이터 도구(BigQuery/Bigtable/Spanner), MCP 툴셋 기본 제공.
- **MCP 프로토콜 연동**: `adk_mcp` 기반의 `McpToolset` 및 `McpSessionManager`를 통해 Streamable HTTP로 원격 MCP 서버 연동.
- **개발자 CLI + Dev Server UI**: `adk` CLI(`create`, `run`, `web`, `api_server`, `deploy`)를 통한 스캐폴딩, 대화형 터미널 런타임 및 웹 디버그 UI 지원.

## ADK Python 호환성 현황

ADK Dart는 Dart 네이티브 정적 타입 시스템, 비동기 스트림(`Stream<Event>`), 패키지 구조 및 플랫폼 제약 조건을 준수하면서 `adk-python`과 동일하게 동작하도록 설계되었습니다. 현재 릴리즈 기준선은 `adk-python` `2.7.0`을 추적합니다.

상태 범례:

- `✅` 구현 완료 및 호환성/런타임 테스트 통과.
- `⚠️` 플랫폼, 자격증명 또는 환경 제약 조건 하에 구현됨.
- `🚧` 향후 계획 / 미구현.

| `adk-python` 영역 | Dart 상태 | Dart 구현 API 및 인터페이스 | 비고 |
| --- | --- | --- | --- |
| 패키지/버전 기준선 | ✅ | `adkVersion`, 패키지 버전 | `adk_dart`, `adk`, `adk_mcp`, `flutter_adk` 최신 정렬 완료; ADK 기준 버전은 `2.7.0`. |
| 에이전트 및 런너 | ✅ | `BaseAgent`, `LlmAgent`/`Agent`, `SequentialAgent`, `ParallelAgent`, `LoopAgent`, `Runner`, `InMemoryRunner` | 핵심 호출, 실시간 폴백, 세션 롤백 및 리와인드(Rewind), 세션 상태, 콜백 및 Agent Transfer 구현 완료. |
| LLM 플로우 프로세서 | ✅ | `flows/llm_flows` 하위 요청/응답 프로세서 | 지침, 정체성, 컨텐츠, 토큰 컴팩션, 컨텍스트 캐시, 코드 실행, 출력 스키마, 툴 확인(HITL), 사전 인증 및 에이전트 전환 처리. |
| 워크플로우 런타임 | ✅ | `Workflow`, `BaseNode`, 함수/도구/LLM-Agent 노드, `NodeTool`(도구화된 워크플로우), 조인, 라우트, 동적 노드, 리플레이 헬퍼 | 재시도, 타임아웃, 입력 요청/HITL, 병렬 워커, 워크플로우 리플레이 및 상태 복원(State Restoration), START 라우팅 가드, 완료 태스크 배칭, 엄격한 입력 스키마 검증, 그래프 직렬화, DOT 시각화 포팅 완료. |
| 이벤트 및 컨텐츠 변환 | ✅ | `Event`, `EventActions`, 컨텐츠/파트 모델, 노드 경로 헬퍼 | 구조화 이벤트 액션, 노드 경로 빌더, 함수/도구 응답 변환, A2A 메타데이터 보존 포함. |
| 세션 및 상태 | ✅ | In-Memory, SQLite, Database, Vertex AI 세션 서비스, 마이그레이션 헬퍼 | 로컬 및 원격 세션 API 구현 완료; 네트워크/클라우드 백엔드는 적절한 자격증명 및 엔드포인트 필요. |
| 메모리 및 아티팩트 | ✅ | In-Memory 메모리, Vertex AI 메모리/RAG, In-Memory/파일/GCS 아티팩트 | GCS/Vertex 경로는 HTTP/인증 프로바이더 연동을 사용하며 실제 클라우드 호출 시 환경 설정 필요. |
| 도구 및 툴셋 | ✅ | 함수 도구, 에이전트 도구, OpenAPI 도구, Google API 도구, 검색/검색증강 도구, 환경 도구, 데이터 도구 | Google 검색, URL 컨텍스트, 코드 실행, 컴퓨터 사용, Google Maps, 엔터프라이즈 웹 검색, Vertex AI 검색, Vertex RAG 내장 지원. |
| MCP 통합 | ⚠️ | `adk_mcp`, `McpToolset`, `McpSessionManager`, `StreamableHTTPConnectionParams`, `StdioConnectionParams` | Streamable HTTP는 HTTP/CORS가 허용되는 VM/Flutter/Web 전반에서 동작. Stdio는 로컬 프로세스 실행이 필요하여 VM 전용. |
| 모델/제공자 | ✅ | Gemini REST/Live, Anthropic, LiteLLM, Gemma, Apigee, Chat Completions, OpenAI labs 어댑터 | 주입 가능한 전송 계층으로 포팅 완료; 실제 호출 시 API 키 및 프로바이더 설정 필요. |
| 인증 및 자격증명 | ✅ | 인증 스키마, 자격증명 매니저/서비스, OAuth2 교환/갱신, 서비스 계정 훅 | 도구 인증, 인증 응답 영속화, OAuth 검색, 토큰 교환/갱신 및 세션 상태 자격증명 저장 지원. |
| 평가 및 시뮬레이션 | ✅ | 평가 매니저/서비스, 지표 평가기, LLM-as-a-judge, 사용자 시뮬레이터 | 로컬/GCS 평가 세트 매니저, 궤적/최종응답/루브릭/안전성 지표, 시뮬레이터 기반 응답 생성 구현. |
| 플러그인 및 텔레메트리 | ✅ | 플러그인 매니저, 디버그/글로벌/반추/아티팩트저장 플러그인, OpenTelemetry/SQLite/클라우드 텔레메트리 | SQLite 트레이스 영속화, 메트릭스 계측, 자동 트레이싱 및 플러그인 생명주기 훅 지원. |
| CLI, 개발 서버, 배포 | ✅ | `adk create/run/web/api_server/deploy/eval/eval_set/conformance/migrate` | Dart CLI 환경에 맞춰 포팅 완료. |
| A2A 프로토콜 | ✅ | A2A 변환기, 실행기, 에이전트 카드, JSON-RPC/REST 태스크 라우트, 원격 A2A 에이전트 | 스트리밍, 태스크 재개/취소/재구독, 푸시 알림 설정, 메타데이터 전파 및 SQLite 기반 영속 푸시 큐 지원. |
| 코드 실행기 | ⚠️ | 로컬 프로세스, 컨테이너/Docker, GKE, Vertex AI, Cloud Run 샌드박스 실행기 | 런타임 로직 구현 완료; 실제 실행은 로컬 Docker/K8s/Vertex/Cloud Run 환경에 의존. |
| 데이터/클라우드 연동 | ⚠️ | BigQuery, Bigtable, Spanner, Pub/Sub, Secret Manager, Agent Registry, Skill Registry, Slack, Toolbox | 런타임 클라이언트 및 파사드 구현 완료; 실제 동작은 클라우드 자격증명 필요. |
| 스킬 (Skills) | ✅ | `Skill`, `SkillToolset`, 로컬/In-Memory/GCS 스킬 소스, 스킬 프롬프트 포맷팅 | 인라인 및 디렉토리 기반 스킬 구현 완료. 파일시스템 기반 로딩은 Flutter Web 미지원. |
| Flutter/Web-Safe API | ⚠️ | `adk_core`, `flutter_adk`, Flutter 예제 앱 | Web-safe 런타임 API 인터페이스 노출, VM 전용 API(`dart:io`, `dart:ffi`, `dart:mirrors` 등)는 안전하게 분리. |
| OpenAPI 외부 참조 | 🚧 | OpenAPI 파서/툴셋 | 인라인 및 로컬 스펙 처리 완료; 외부 멀티 파일 `$ref` 해석 지원 예정. |
| Spanner PostgreSQL ANN | 🚧 | Spanner 벡터 도구 | Spanner/Vector 핵심 경로 구현 완료; PostgreSQL ANN 동작은 향후 지원 예정. |
| 음성 텍스트 변환 런타임 | ⚠️ | 오디오 음성 인식(STT) 런타임 | 음성 텍스트 변환(Speech-to-Text) 오케스트레이션 제공; 인스턴스별 인식기 전달 또는 기본 인식기 등록 필요. |
| Python 샘플 트리 커버리지 | 🚧 | 예제, `flutter_adk/example`, 문서 | 대표적인 Dart/Flutter 예제 제공; Python 전체 샘플 트리는 점진적 확장 중. |

## 생태계 아키텍처 및 패키지 선택 가이드

```
+-------------------------------------------------------------------------------+
|                                    adk                                        |
|              (공식 CLI 툴체인 실행 바이너리 & 최상위 통합 엔트리포인트)               |
+-------------------------------------------------------------------------------+
       |                                                    |
       v (의존)                                              v (의존)
+------------------------------------+   +------------------------------------+
|             adk_dart               |   |            flutter_adk             |
|   (에이전트 코어 런타임 및 SDK 엔진)  |   |  (Flutter 멀티플랫폼 & Web Safe API)|
+------------------------------------+   +------------------------------------+
       |                                                    |
       +--------------------+-------------------------------+
                            |
             +--------------+--------------+
             |                             |
             v                             v
+--------------------------+  +--------------------------+
|         adk_mcp          |  |       adk_litertlm       |
| (Model Context Protocol) |  | (온디바이스 LiteRT/Gemini) |
+--------------------------+  +--------------------------+
```

| 개발 환경 및 목적 | 권장 패키지 | 역할 및 핵심 가치 |
| :--- | :--- | :--- |
| 터미널에서 CLI 도구 실행 (`adk create`, `adk run`, `adk web`) 또는 백엔드 에이전트 개발 | [`adk`](https://pub.dev/packages/adk) | 공식 CLI 실행 바이너리 및 Dart VM 최상위 통합 엔트리포인트 |
| 코어 SDK 프리미티브 기반 백엔드/클라우드/서버 에이전트 개발 | [`adk_dart`](https://pub.dev/packages/adk_dart) | 에이전트, 러너, 워크플로우 2.0 엔진을 제공하는 SDK 핵심 라이브러리 |
| Flutter 클라이언트 앱 개발 (모바일, 데스크톱, 웹) | [`flutter_adk`](https://pub.dev/packages/flutter_adk) | 플랫폼 채널 및 Web-safe 정제 런타임(`adk_core`) 제공 |
| MCP(Model Context Protocol) 클라이언트/서버 연동 | [`adk_mcp`](https://pub.dev/packages/adk_mcp) | 독립형 표준 MCP 프로토콜 전송/세션 패키지 |
| 온디바이스 엣지 디바이스 Gemini Nano / LiteRT 가속 | [`adk_litertlm`](https://pub.dev/packages/adk_litertlm) | 온디바이스 경량 LLM 런타임 통합 패키지 |

빠른 선택 가이드:

- 터미널에서 `adk` CLI를 사용하거나 통합 패키지를 쓸 때는 `adk`를 선택하세요.
- 코어 SDK 라이브러리에 직접 의존할 때는 `adk_dart`를 선택하세요.
- Flutter 앱 개발 시에는 `flutter_adk`를 선택하세요.

## 플랫폼 지원 매트릭스

| 기능 / 영역 | Dart VM / CLI | Flutter (Android/iOS/Linux/macOS/Windows) | Flutter Web | 비고 |
| --- | --- | --- | --- | --- |
| `package:adk_dart/adk_dart.dart` 전체 API | Y | Partial | N | 전체 API에는 `dart:io`, `dart:ffi`, `dart:mirrors` 경로가 포함되어 웹에서는 직접 사용 불가. |
| `package:adk_dart/adk_core.dart` Web-safe API | Y | Y | Y | `adk_core`는 IO/FFI/mirrors 전용 API를 안전하게 분리. |
| 에이전트 런타임 (`Agent`, `Runner`, Workflows) | Y | Y | Y | In-memory 오케스트레이션 경로는 완전한 크로스플랫폼. |
| MCP over Streamable HTTP (`StreamableHTTPConnectionParams`) | Y | Y | Y | HTTP가 가능한 환경에서 동작 (웹은 MCP 서버 CORS 설정 필요 가능). |
| MCP over stdio (`StdioConnectionParams`) | Y | Partial | N | `dart:io` `Process`를 통한 로컬 프로세스 실행 필요 (웹 미지원). |
| 인라인 스킬 (`Skill` + `SkillToolset`) | Y | Y | Y | 인라인 스킬 정의는 Web-safe. |
| 디렉토리 기반 스킬 로딩 (`loadSkillFromDir`) | Y | Partial | N | 파일시스템 API 사용 (웹에서는 `UnsupportedError` 발생). |
| CLI (`adk create/run/web/api_server/deploy`) | Y | N | N | CLI는 VM/터미널 전용. |
| 개발 웹 서버 + A2A 서비스 엔드포인트 | Y | N | N | 서버 호스팅 경로는 VM 런타임 전용. |
| DB/파일 기반 서비스 (SQLite/Postgres/MySQL 세션, 파일 아티팩트) | Y | Partial | N | IO/네트워크/파일 프리미티브에 의존. |

## 설치 방법

### 최신 안정화 버전 (권장)

```bash
dart pub add adk_dart
```

짧은 import 패키지(`adk`)를 사용하는 경우:

```bash
dart pub add adk
```

### 개발 버전 (Git 참조)

```yaml
dependencies:
  adk_dart:
    git:
      url: https://github.com/adk-labs/adk_dart.git
      ref: main
```

```bash
dart pub get
```

## Gemini API 환경 변수 설정

ADK Dart는 다음 환경 변수명을 기본으로 권장합니다:

- `GOOGLE_API_KEY` (권장)

호환성을 위해 `GEMINI_API_KEY` 별칭도 함께 지원합니다.

### 옵션 A: Gemini API 모드 (기본값)

```env
GOOGLE_GENAI_USE_VERTEXAI=0
GOOGLE_API_KEY=your_google_api_key
```

### 옵션 B: Vertex AI 모드

```env
GOOGLE_GENAI_USE_VERTEXAI=1
GOOGLE_CLOUD_PROJECT=your-gcp-project-id
GOOGLE_CLOUD_LOCATION=us-central1
GOOGLE_API_KEY=your_google_api_key
```

## MCP (Model Context Protocol)

ADK Dart는 MCP 지원을 기본 내장하며, 프로토콜 프리미티브를 별도 패키지로 제공합니다:

- `packages/adk_mcp`: Dart용 MCP 전송/생명주기 코어
- `adk_dart` MCP 계층: ADK 도구/런타임 연동 (`McpToolset`, `McpSessionManager`, `LoadMcpResourceTool`, `McpInstructionProvider`)

## 기능 하이라이트 코드 예제

### 단일 에이전트 정의

```dart
import 'package:adk_dart/adk_dart.dart';

class EchoModel extends BaseLlm {
  EchoModel() : super(model: 'echo');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String userText = request.contents.isEmpty
        ? ''
        : request.contents.last.parts
              .where((Part part) => part.text != null)
              .map((Part part) => part.text!)
              .join(' ');

    yield LlmResponse(content: Content.modelText('echo: $userText'));
  }
}

Future<void> main() async {
  final Agent agent = Agent(name: 'echo_agent', model: EchoModel());
  final InMemoryRunner runner = InMemoryRunner(agent: agent);

  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'user_1',
    sessionId: 'session_1',
  );

  await for (final Event event in runner.runAsync(
    userId: 'user_1',
    sessionId: session.id,
    newMessage: Content.userText('hello'),
  )) {
    print(event.content?.parts.first.text ?? '');
  }
}
```

### 멀티 에이전트 시스템 구성

```dart
import 'package:adk_dart/adk_dart.dart';

class StubModel extends BaseLlm {
  StubModel() : super(model: 'stub');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText('done'));
  }
}

void main() {
  final Agent greeter = Agent(
    name: 'greeter',
    model: StubModel(),
    instruction: 'Handle greetings.',
  );

  final Agent worker = Agent(
    name: 'worker',
    model: StubModel(),
    instruction: 'Handle execution tasks.',
  );

  final Agent coordinator = Agent(
    name: 'coordinator',
    model: StubModel(),
    instruction: 'Route requests to sub-agents.',
    subAgents: <BaseAgent>[greeter, worker],
  );

  print('Coordinator configured: ${coordinator.name}');
}
```

### 개발용 CLI 및 Web UI

```bash
dart pub global activate adk_dart
adk create my_agent
cd my_agent
adk run .
adk web --port 8000 .
```

`adk web` 명령은 `http://127.0.0.1:8000`에서 로컬 개발 서버 및 대화형 디버그 UI를 호스팅합니다.

## 테스트

```bash
dart test
dart analyze
```

## 라이선스

이 프로젝트는 Apache 2.0 라이선스 하에 배포됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요.
