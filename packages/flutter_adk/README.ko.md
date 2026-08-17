# flutter_adk

[English](README.md) | 한국어 | [日本語](README.ja.md) | [中文](README.zh.md)

ADK Dart 코어 런타임을 위한 Flutter 파사드 패키지 및 완성형 UI Kit입니다.

[![pub package](https://img.shields.io/pub/v/flutter_adk.svg)](https://pub.dev/packages/flutter_adk)
[![WASM Ready](https://img.shields.io/badge/Flutter%20Web-WASM%20100%25-brightgreen.svg)](https://flutter.dev/to/wasm)

## 주요 제공 기능
- **단일 import 파사드**: `package:adk_dart/adk_core.dart`를 재노출하여 iOS, Android, macOS, Windows, Linux, **Flutter Web(WASM / dart2wasm)** 전체 플랫폼에서 안전하게 동작합니다.
- **완성형 UI Kit**: 대화창, 개발자 스튜디오, I/O 로거, 툴 인스펙터, 구조화 데이터 뷰어, 워크플로우 진행률 바, 음성 인터랙션 위젯 제공.
- **플러그앤플레이 세션 영구화**: `SharedPreferences`, `FlutterSecureStorage`, SQLite, Hive 등과 2줄로 연동되는 `AdkStorageSessionService`.
- **코어 런타임**:
  - `Agent` / `LlmAgent` (기본 모델: `gemini-3.7-flash`, 로컬 `LiteLlm` Ollama/LM Studio)
  - 워크플로우: `SequentialAgent`, `ParallelAgent`, `LoopAgent`, `ManagedAgent`
  - 도구(Tools): `FunctionTool`, `AgentTool`, `McpToolset` (Streamable HTTP), `SkillToolset`
  - 정보 검색: `UrlContextTool`, `VertexAiSearchTool`, `VertexRagRetrievalTool`

---

## 설치 방법

```bash
flutter pub add flutter_adk
```

또는 `pubspec.yaml`:

```yaml
dependencies:
  flutter_adk: ^2026.8.17+7
```

---

## 빠른 시작 (완성형 챗 UI)

단 몇 줄의 코드로 Flutter 앱에 대화형 AI 에이전트 챗 화면을 즉시 배치할 수 있습니다:

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
      instruction: '친절하고 똑똑한 Flutter 어시스턴트입니다.',
    );

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('ADK Flutter Chat')),
        // 2. 완성형 챗 위젯 배치 (또는 AdkDevStudioView로 대시보드 전체 임베드)
        body: AdkChatView(
          agent: agent,
          inputPlaceholder: '무엇이든 질문해 보세요...',
        ),
      ),
    );
  }
}
```

---

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

---

# 📚 위젯 및 API 상세 명세서 (Specification)

### 1. 완성형 뷰 및 개발자 도구 (Turnkey Views)

| 위젯 명 | 설명 | 주요 파라미터 |
|---|---|---|
| **`AdkChatView`** | 자동 스크롤, 입력창, 추천 질문 칩, 도구 실행 카드가 통합된 완성형 대화창 | `agent`, `controller`, `suggestions`, `showVoiceButton`, `customBubbleBuilder`, `inputPlaceholder` |
| **`AdkDevStudioView`** | ADK Web을 플러터에 이식한 개발자 스튜디오 (Playground, Live Logger, Agent Graph, Session State 탭 통합) | `agent`, `controller`, `initialTab`, `showLogs` |
| **`AdkAgentLoggerView`** | 프롬프트, 모델 응답, 도구 호출/결과, 지연 시간(ms), 토큰 소모량을 실시간 추적하고 검색/필터링/복사 지원 | `logs`, `onClearLogs`, `showHeader`, `title` |
| **`AdkToolInspectorView`** | 에이전트에 등록된 모든 도구 목록과 각 도구의 JSON 파라미터 스키마를 시각화 | `tools`, `title`, `showHeader` |
| **`AdkStructuredDataView`** | `outputSchema` 기반 JSON 구조화 응답을 위한 프리티 프린팅 및 원클릭 복사 뷰어 | `data`, `title`, `allowCopy`, `initialExpanded` |

---

### 2. 상태 컨트롤러 및 스토리지 서비스

#### `AdkChatController`
대화 히스토리, 멀티 청크 실시간 스트리밍, 도구 실행, 스토리지 저장을 통합 관리하는 `ChangeNotifier` 기반 컨트롤러입니다.

- **생성자**:
  - `AdkChatController({BaseAgent? agent, Runner? runner, String? userId, String? appName, String? sessionId, BaseSessionService? sessionService})`
  - `AdkChatController.fromStorage({required BaseAgent agent, required AdkKeyValueStorage storage, ...})`
- **핵심 메서드**:
  - `Future<void> sendMessage(String text)`: 사용자 입력을 전송하고 모델/도구 스트림을 `messages`에 실시간 반영합니다.
  - `Future<void> loadSession({String? targetSessionId})`: 스토리지에 저장된 이전 대화 기록을 불러옵니다.
  - `String exportTranscriptJson({bool pretty = true})`: 대화 전체를 JSON 문자열로 내보냅니다.
  - `void stopGeneration()`: 현재 진행 중인 스트리밍 생성을 즉시 취소합니다.
  - `void clearMessages()`: 메시지 목록을 비우고 에러 상태를 초기화합니다.

#### `AdkStorageSessionService`
`SharedPreferences`, `FlutterSecureStorage` 등 모든 Key-Value 저장소를 2줄로 연결하는 세션 영구화 서비스입니다.

```dart
// SharedPreferences 2줄 연동:
final sessionService = AdkStorageSessionService.custom(
  read: (key) => prefs.getString(key),
  write: (key, value) => prefs.setString(key, value),
  delete: (key) => prefs.remove(key),
  getKeys: ({prefix = ''}) => prefs.getKeys().where((k) => k.startsWith(prefix)).toList(),
);
```

#### `AdkTheme` & `AdkChatThemeData` (테마 커스터마이징)
앱 또는 특정 화면을 `AdkTheme`으로 감싸면 말풍선 색상, 코너 라운딩, 폰트 스타일, 패딩을 일괄 적용할 수 있습니다:

```dart
AdkTheme(
  data: const AdkChatThemeData(
    userBubbleColor: Colors.deepPurple,
    modelBubbleColor: Color(0xFFF1F5F9),
    userTextColor: Colors.white,
    modelTextColor: Colors.black87,
    borderRadius: BorderRadius.all(Radius.circular(20.0)),
    inputBackgroundColor: Colors.white,
    sendButtonColor: Colors.deepPurple,
    showTimestamp: true,
    showAvatars: true,
  ),
  child: AdkChatView(agent: myAgent),
)
```

---

### 3. 인터랙티브 UI 컴포넌트 및 커스텀 빌더 슬롯

| 컴포넌트 | 설명 | 사용 예시 |
|---|---|---|
| **`showAdkChatBottomSheet`** | 한 줄로 호출하는 대화형 AI 상담원 모달 바텀시트 | `showAdkChatBottomSheet(context: context, agent: myAgent);` |
| **`AdkSplitPaneView`** | 웹/태블릿/데스크톱용 적응형 분할 뷰 (좌: 챗 / 우: 로거 & 도구 인스펙터) | `AdkSplitPaneView(agent: myAgent, splitRatio: 0.55);` |
| **`AdkReasoningExpander`** | Gemini 3.7 Thinking 사고 과정 아코디언 확장 뷰어 | `AdkReasoningExpander(thought: msg.thought!, durationMs: 1200);` |
| **`AdkAgentPersonaSelector`** | 멀티 에이전트 페르소나 선택 그리드/캐러셀 카드 템플릿 | `AdkAgentPersonaSelector(personas: [...], onPersonaSelected: (p) => ...);` |
| **`AdkInlineAssistantBar`** | 입력창용 인라인 Copilot 툴바 (문법 교정, 톤 변경, 요약, 번역) | `AdkInlineAssistantBar(agent: copyAgent, targetController: textCtrl);` |
| **`AdkSmartFormView`** | 대화를 통해 폼 필드가 실시간으로 채워지는 스마트 폼 템플릿 | `AdkSmartFormView(agent: formAgent, fields: [...], onSubmit: (data) => ...);` |
| **`AdkConfirmationBanner`** | 민감한 도구 실행 전 사용자 승인을 받는 인간 참여(HITL) 배너 및 모달 다이얼로그 | `AdkConfirmationBanner.showAsDialog(context, title: '도구 승인', description: '...');` |
| **`AdkSessionDrawer`** | 대화 세션 히스토리 목록 탐색, 세션 전환, 생성(`+`), 삭제 지원 드로어 | `AdkSessionDrawer(sessions: sessions, activeSessionId: id, onSessionSelected: (s) => ...);` |
| **`AdkFloatingChatButton`** | 탭 시 모달 바텀시트 챗창이 열리는 플로팅 액션 버튼(FAB) | `AdkFloatingChatButton(agent: myAgent);` |
| **`AdkPromptSuggestionsBar`** | 가로 스크롤 추천 질문 칩 바 | `AdkPromptSuggestionsBar(suggestions: [...], onSelected: (s) => ...);` |
| **`AdkToolCallCard`** | 도구 이름, 전달 인자, 실행 상태, 반환 결과를 보여주는 아코디언 카드 | `AdkToolCallCard(toolName: 'search', arguments: {...}, result: {...});` |
| **`AdkWorkflowProgressIndicator`**| 워크플로우 각 노드의 실행 타임라인 진행률 바 | `AdkWorkflowProgressIndicator(steps: workflowSteps);` |
| **`AdkAgentHierarchyBadge`** | 멀티 에이전트 트리 계층에서 현재 활성 에이전트를 표시하는 뱃지 | `AdkAgentHierarchyBadge(agentPath: ['Supervisor', 'Researcher']);` |
| **`AdkTokenUsageBadge`** | 입력/출력 토큰 소모량을 작게 보여주는 뱃지 | `AdkTokenUsageBadge(promptTokens: 120, completionTokens: 80);` |
| **`AdkVoiceMicButton` & `AdkAudioWaveVisualizer`** | 실시간 음성 마이크 버튼 및 오디오 파형 애니메이션 위젯 | `AdkVoiceMicButton(isListening: true, onPressed: () => ...);` |
| **`AdkMessageBubble`** | 사용자, 모델, 툴, 추론 과정, 에러를 명확히 구분하는 Material 3 메시지 버블 | `AdkMessageBubble(message: chatMessage);` |
| **`AdkTypingIndicator`** | AI 생각/타이핑 펄스 인디케이터 | `AdkTypingIndicator();` |
| **`AdkEventStreamBuilder`** | ADK의 실시간 `Stream<Event>`를 즉시 수신하여 반응형 UI를 구성하는 전용 빌더 | `AdkEventStreamBuilder(stream: runner.runAsync(...), builder: (ctx, events) => ...);` |

---

### 4. UI 데이터 모델 (`package:flutter_adk/flutter_adk.dart`)

- **`AdkChatMessage`**: 불변 대화 메시지 모델 (`isUser`, `isModel`, `isTool`, `isSystem`, `isStreaming`, `thought`, `toolArgs`, `toolResult`, `metadata`).
- **`AdkToolCallInfo`**: 도구 실행 상태 모델 (`callId`, `toolName`, `arguments`, `result`, `status`, `durationMs`).
- **`AdkWorkflowStep`**: 워크플로우 단계 모델 (`id`, `label`, `description`, `status`, `durationMs`, `output`).
- **`AdkSessionInfo`**: 세션 정보 모델 (`id`, `title`, `messageCount`, `lastMessagePreview`, `updatedAt`).
- **`AdkPromptSuggestion`**: 추천 질문 모델 (`text`, `label`, `icon`, `category`).
- **`AdkTokenUsage`**: 토큰 사용량 모델 (`promptTokens`, `completionTokens`, `totalTokens`, `formattedTotal`).
- **`AdkVoiceState`**: 실시간 음성 상태 모델 (`status`, `decibels`, `isMuted`, `isActive`).

---

## 플랫폼 지원 매트릭스

| 기능 | Android | iOS | Web (WASM) | Linux | macOS | Windows | 비고 |
| --- | :---: | :---: | :---: | :---: | :---: | :---: | --- |
| `flutter_adk` 단일 import | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Web-safe `adk_core` 재노출 |
| 완성형 UI Kit (14+종 위젯) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 100% Flutter Material 3 |
| Agent 런타임 (`LlmAgent`, 워크플로우) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Pure Dart 비동기 스트림 오케스트레이션 |
| `Gemini` (3.7 / 2.0) & `LiteLlm` (로컬) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 크로스플랫폼 REST & WebSocket |
| MCP Toolset (Streamable HTTP) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 원격 MCP HTTP 서버 연결 |
| 스토리지 서비스 (`AdkStorageSessionService`)| ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 모든 Key-Value 저장소 호환 |

---

## 라이선스

Apache License 2.0. Developed with ❤️ by Deepmind & ADK Labs.
