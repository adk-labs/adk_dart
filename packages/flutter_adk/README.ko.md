# flutter_adk

[English](README.md) | 한국어 | [日本語](README.ja.md) | [中文](README.zh.md)

Flutter 앱에서 ADK Dart 코어 런타임을 Web-safe API 계층으로 사용하기 위한 파사드 패키지입니다.

## 제공 항목

- `package:adk_dart/adk_core.dart` 재노출
- Flutter 단일 import 경로: `package:flutter_adk/flutter_adk.dart`
- `AgentTool`, `UrlContextTool`, Vertex retrieval tool 같은 최신 Web-safe ADK API 포함
- 주요 Flutter 플랫폼(Android/iOS/Web/Linux/macOS/Windows) 플러그인 등록

## 언제 `flutter_adk`를 쓰면 좋나요?

`flutter_adk`를 선택하세요:

- Flutter 앱에서 모바일/데스크톱/Web을 하나의 import로 다루고 싶을 때
- VM 전용 API를 기본으로 끌어오지 않고 Web-safe `adk_core` API 계층을 쓰고 싶을 때

다른 패키지를 선택하세요:

- VM/CLI 에이전트/도구/서버 개발: `adk_dart` (짧은 import는 `adk`)

설계 의도:

- `flutter_adk`는 단순 래퍼 이름이 아니라 Flutter 호환 계층입니다.
- 전체 VM 전용 API를 그대로 노출하기보다 Web-safe 런타임 API(`adk_core`)를
  중심으로 제공해 Flutter 멀티플랫폼에서 동작 일관성을 우선합니다.

## 패키지 링크

- [flutter_adk](https://pub.dev/packages/flutter_adk): Flutter
  멀티플랫폼에서 사용할 Web-safe ADK API를 제공하는 패키지입니다.
- [adk_dart](https://pub.dev/packages/adk_dart): 전체 ADK Dart VM/CLI
  런타임 API를 제공하는 코어 패키지입니다.
- [adk](https://pub.dev/packages/adk): `adk_dart`를 짧은 이름으로
  재노출하는 파사드 패키지입니다.

## ADK 2.0 호환성

이 패키지는 ADK 2.0과 정렬되어 있어, v2 워크플로(선언적 노드 그래프 스케줄링, 조건부 라우팅 및 상태 병합)와 하이브리드 온디바이스 + 클라우드 실행을 위한 GCP Managed Agent 연동(`ManagedAgent` 및 `RemoteMcpServer` 설정 매핑)을 지원합니다.

## 플랫폼 지원 매트릭스 (현재)

상태 표기:

- `Y` 지원
- `Partial` 주의사항과 함께 지원
- `N` 미지원

| 기능 | Android | iOS | Web | Linux | macOS | Windows | 비고 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `flutter_adk` 단일 import | Y | Y | Y | Y | Y | Y | Web-safe `adk_core` API 재노출 |
| Agent 런타임 (`Agent`, `Runner`, workflows) | Y | Y | Y | Y | Y | Y | in-memory 경로는 공통 |
| `Gemini` 모델 사용 | Y | Y | Partial | Y | Y | Y | Web BYOK/CORS/보안 정책 고려 필요 |
| Built-in model tools (`UrlContextTool`, Vertex retrieval) | Y | Y | Y | Y | Y | Y | Gemini/Vertex backend에서 tool 실행 |
| MCP Toolset (Streamable HTTP) | Y | Y | Y | Y | Y | Y | 원격 MCP HTTP 서버 연결 |
| MCP Toolset (stdio) | Partial | Partial | N | Y | Y | Y | Web 불가, 모바일은 프로세스 정책 영향 가능 |
| Skills (inline) | Y | Y | Y | Y | Y | Y | 인라인 스킬은 크로스플랫폼 |
| 디렉토리 스킬 로딩 (`loadSkillFromDir`) | Y | Y | N | Y | Y | Y | Web에서 `UnsupportedError` |
| 플러그인 채널 helper (`getPlatformVersion`) | Y | Y | Y | Y | Y | Y | 플랫폼 채널 / 브라우저 user-agent |
| VM/CLI 도구 (`adk`, dev server, deploy path) | N | N | N | N | N | N | Flutter 패키지 범위 밖 |

## 설치

```bash
flutter pub add flutter_adk
```

또는 `pubspec.yaml`:

```yaml
dependencies:
  flutter_adk: ^2026.8.17+3
```

## 빠른 시작 (완성형 챗 UI)

단 몇 줄의 코드로 Flutter 앱에 대화형 AI 에이전트 챗 화면을 즉시 탑재할 수 있습니다:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. AI 에이전트 정의 (기본 모델: gemini-3.7-flash)
    final agent = LlmAgent(
      name: 'assistant',
      model: 'gemini-3.7-flash',
      instruction: '친절하고 똑똑한 플러터 어시스턴트입니다.',
    );

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('ADK AI Assistant')),
        // 2. 완성형 챗 위젯 배치 (또는 AdkDevStudioView로 대시보드 전체 임베드 가능)
        body: AdkChatView(
          agent: agent,
          inputPlaceholder: '무엇이든 질문해 보세요...',
        ),
      ),
    );
  }
}
```

## 로컬 LLM 빠른 시작 (Ollama / LM Studio)

클라우드 API 키 없이 완전히 오프라인으로 로컬 모델 기반 AI 에이전트를 구동할 수 있습니다:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';

void main() => runApp(const LocalAiApp());

class LocalAiApp extends StatelessWidget {
  const LocalAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 로컬 Ollama(http://localhost:11434/v1) 또는 LM Studio(http://localhost:1234/v1) 연결
    final localModel = LiteLlm(
      model: 'ollama_chat/gemma2:2b',
      baseUrl: 'http://localhost:11434/v1',
    );

    final agent = Agent(
      name: 'local_assistant',
      model: localModel,
      instruction: '빠르고 안전한 오프라인 로컬 AI 어시스턴트입니다.',
    );

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('오프라인 로컬 LLM 챗')),
        body: AdkChatView(agent: agent),
      ),
    );
  }
}
```

## 내장 UI 컴포넌트 및 컨트롤러

`flutter_adk`는 Flutter 앱에 즉시 적용 가능한 12종 이상의 UI 위젯과 상태 컨트롤러를 제공합니다:
- **`AdkDevStudioView`**: `adk web`을 플러터 화면에 그대로 이식한 완성형 개발자 스튜디오 (Playground, Live Logger, Agent Graph, State 통합 탭)
- **`AdkAgentLoggerView`**: 에이전트 입출력, LLM 응답, 툴 호출, 지연 시간(ms), 상태 변화를 실시간으로 모니터링하고 JSON 복사를 지원하는 전문 로거
- **`AdkChatView`**: 자동 스크롤, 입력창, 추천 질문 바, 음성 트리거가 통합된 완성형 챗 위젯
- **`AdkChatController`**: 세션 및 스트리밍 상태 관리를 지원하는 ChangeNotifier 기반 컨트롤러
- **`AdkFloatingChatButton`**: 탭 시 모달 바텀시트 챗창이 열리는 플로팅 액션 버튼(FAB)
- **`AdkPromptSuggestionsBar`**: 클릭 한 번으로 질문을 발화할 수 있는 추천 프롬프트 칩 바
- **`AdkToolCallCard`**: 툴 이름, 인자, 실행 상태, 결과를 시각화하는 아코디언 카드
- **`AdkConfirmationBanner` & `AdkConfirmationDialog`**: 인간 참여(HITL) 작업 승인/거부 배너 및 모달 팝업
- **`AdkSessionDrawer`**: 대화 세션 히스토리 목록 탐색, 생성(+), 삭제 드로어
- **`AdkAgentHierarchyBadge`**: 멀티 에이전트 계층 구조에서 현재 활성 에이전트를 보여주는 브레드크럼 뱃지
- **`AdkWorkflowProgressIndicator`**: ADK 2.0 워크플로우 노드 실행 타임라인 진행률 바
- **`AdkVoiceMicButton` & `AdkAudioWaveVisualizer`**: 음성 마이크 버튼 및 실시간 오디오 파형 애니메이션 위젯
- **`AdkTokenUsageBadge`**: 입력/출력 토큰 소모량을 작게 보여주는 뱃지
- **`AdkStructuredDataView`**: `outputSchema` 기반 구조화된 JSON 응답을 위한 프리티 프린팅 및 복사 기능 지원 뷰어.
- **`AdkToolInspectorView`**: 에이전트에 등록된 모든 툴 목록과 JSON 파라미터 스키마를 트리 형태로 조회하는 인스펙터.
- **`AdkMessageBubble`**: 사용자, 모델, 툴 실행 결과를 명확히 구분하는 Material 3 스타일 메시지 버블.
- **`AdkTypingIndicator`**: 부드러운 펄스 애니메이션이 적용된 AI 생각/타이핑 인디케이터.
- **`AdkEventStreamBuilder`**: ADK의 실시간 `Stream<Event>`를 즉시 수신하여 반응형 UI를 구성하는 전용 빌더.

## 참고

- 상세 기능/제약: [README.md](README.md)
- 플랫폼 심화 노트: `knowledge/2026-03-01_18-20-00_flutter_adk_platform_support_matrix.md`
