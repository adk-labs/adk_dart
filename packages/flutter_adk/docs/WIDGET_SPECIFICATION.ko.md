# Flutter ADK 위젯 기술 명세서 (Widget Specification)

본 문서는 `flutter_adk` 패키지에 포함된 전체 UI 위젯 및 컴포넌트에 대한 상세 기술 명세서입니다.

`flutter_adk`는 Google Agent Development Kit (ADK) Dart 코어 런타임을 위한 공식 Flutter UI Kit 및 파사드입니다. Material 3 디자인 시스템 준수, 접근성 지원, 그리고 **Flutter Web (WASM / dart2wasm)** 환경을 100% 지원합니다.

---

## 목차

1. [아키텍처 개요 및 설계 원칙](#1-아키텍처-개요-및-설계-원칙)
2. [통합 뷰 및 스캐폴드 위젯](#2-통합-뷰-및-스캐폴드-위젯)
   - [AdkChatView](#adkchatview)
   - [AdkDevStudioView](#adkdevstudioview)
   - [AdkSplitPaneView](#adksplitpaneview)
   - [AdkAgentManagementView](#adkagentmanagementview)
   - [AdkSmartFormView](#adksmartformview)
   - [AdkAgentLoggerView](#adkagentloggerview)
   - [AdkToolInspectorView](#adktoolinspectorview)
   - [AdkArtifactViewer 및 AdkArtifactCard](#adkartifactviewer-및-adkartifactcard)
3. [모달, 드로어 및 플로팅 위젯](#3-모달-드로어-및-플로팅-위젯)
   - [showAdkChatBottomSheet](#showadkchatbottomsheet)
   - [AdkFloatingChatButton](#adkfloatingchatbutton)
   - [AdkSessionDrawer](#adksessiondrawer)
4. [대화 피드 및 메시지 컴포넌트](#4-대화-피드-및-메시지-컴포넌트)
   - [AdkMessageBubble](#adkmessagebubble)
   - [AdkTypingIndicator](#adktypingindicator)
   - [AdkReasoningExpander](#adkreasoningexpander)
   - [AdkPromptSuggestionsBar](#adkpromptsuggestionsbar)
   - [AdkInlineAssistantBar](#adkinlineassistantbar)
5. [도구 실행, 코드 및 검색 출처](#5-도구-실행-코드-및-검색-출처)
   - [AdkToolCallCard](#adktoolcallcard)
   - [AdkCodeExecutionCard](#adkcodeexecutioncard)
   - [AdkGroundingSourcesBar](#adkgroundingsourcesbar)
   - [AdkStructuredDataView](#adkstructureddataview)
6. [Human-in-the-Loop 및 실행 인터럽트](#6-human-in-the-loop-및-실행-인터럽트)
   - [AdkConfirmationBanner 및 AdkConfirmationDialog](#adkconfirmationbanner-및-adkconfirmationdialog)
   - [AdkHumanInTheLoopCard](#adkhumanintheloopcard)
   - [AdkInterruptBanner](#adkinterruptbanner)
   - [AdkInterruptCard](#adkinterruptcard)
7. [실시간 멀티모달 및 음성 스트리밍](#7-실시간-멀티모달-및-음성-스트리밍)
   - [AdkCascadeLiveBar](#adkcascadelivebar)
   - [AdkLiveBargeInIndicator](#adklivebargeinindicator)
   - [AdkVoiceMicButton 및 AdkAudioWaveVisualizer](#adkvoicemicbutton-및-adkaudiowavevisualizer)
8. [워크플로우, 라우팅 및 다중 모델 시각화](#8-워크플로우-라우팅-및-다중-모델-시각화)
   - [AdkWorkflowGraphView](#adkworkflowgraphview)
   - [AdkWorkflowProgressIndicator](#adkworkflowprogressindicator)
   - [AdkClassifierCard](#adkclassifiercard)
   - [AdkModelConsultBadge 및 AdkEscalationCard](#adkmodelconsultbadge-및-adkescalationcard)
   - [AdkAgentHierarchyBadge](#adkagenthierarchybadge)
   - [AdkAgentPersonaSelector](#adkagentpersonaselector)
9. [원격 측정 및 반응형 스트림 빌더](#9-원격-측정-및-반응형-스트림-빌더)
   - [AdkTokenUsageBadge](#adktokenusagebadge)
   - [AdkEventStreamBuilder](#adkeventstreambuilder)
10. [ADK UI 유틸리티](#10-adk-ui-유틸리티)
11. [테마 시스템 (AdkTheme & AdkChatThemeData)](#11-테마-시스템-adktheme--adkchatthemedata)

---

## 1. 아키텍처 개요 및 설계 원칙

1. **완성형 턴키(Turnkey) 구성**: 단 한 줄로 에이전트 대화창 배치 (`AdkChatView(agent: myAgent)`).
2. **풍부한 커스터마이징 훅**: 색상, 여백, 둥글기, 그림자뿐만 아니라 빌더 콜백(`builder`)을 제공하여 UI의 각 구성 요소를 원하는 형태로 교체 가능.
3. **반응형 스트리밍 연동**: ADK 코어 런타임의 `Stream<Event>`와 `AdkChatController`를 통한 실시간 동기화.
4. **WASM 100% 호환**: UI 레이어에서 순수 Dart와 Flutter Web-safe API만 사용하여 브라우저 WASM 컴파일 완벽 지원.

---

## 2. 통합 뷰 및 스캐폴드 위젯

### `AdkChatView`
AI 에이전트와의 실시간 메시지 스트리밍, 사고 과정(Reasoning), 도구 실행 카드, 추천 프롬프트 칩을 제공하는 최상위 대화 인터페이스입니다.

- **클래스**: `StatefulWidget`
- **파일**: [`adk_chat_view.dart`](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/packages/flutter_adk/lib/src/widgets/adk_chat_view.dart)

#### 파라미터 명세

| 파라미터 | 타입 | 필수 여부 | 기본값 | 설명 |
| :--- | :--- | :---: | :--- | :--- |
| `controller` | `AdkChatController?` | 선택 | `null` | 외부 주입 컨트롤러 (생략 시 `agent` 또는 `runner`로 자동 생성) |
| `agent` | `BaseAgent?` | 선택 | `null` | 대화 대상 에이전트 |
| `runner` | `Runner?` | 선택 | `null` | 대화 실행 런타임 러너 |
| `theme` | `AdkChatThemeData?` | 선택 | `null` | 위젯 개별 테마 설정 |
| `title` | `String` | 선택 | `'AI Assistant'` | 앱바 제목 |
| `inputPlaceholder` | `String` | 선택 | `'Ask something...'` | 입력창 플레이스홀더 |
| `suggestions` | `List<String>?` | 선택 | `null` | 하단 추천 프롬프트 칩 목록 |
| `emptyStateWidget` | `Widget?` | 선택 | `null` | 대화 내역이 없을 때 표시할 정적 위젯 |
| `emptyStateBuilder` | `Widget Function(BuildContext)?` | 선택 | `null` | 빈 상태 화면 커스텀 빌더 |
| `messageBubbleBuilder` | `Widget Function(BuildContext, AdkChatMessage)?` | 선택 | `null` | 메시지 버블 렌더링 커스텀 빌더 |
| `avatarBuilder` | `Widget Function(BuildContext, AdkChatMessage)?` | 선택 | `null` | 아바타 커스텀 빌더 |
| `inputBarBuilder` | `Widget Function(BuildContext, TextEditingController, VoidCallback, bool)?` | 선택 | `null` | 텍스트 입력창 및 전송 버튼 커스텀 빌더 |
| `suggestionBuilder` | `Widget Function(BuildContext, String, VoidCallback)?` | 선택 | `null` | 개별 추천 칩 커스텀 빌더 |
| `typingIndicatorBuilder` | `Widget Function(BuildContext)?` | 선택 | `null` | 타이핑 인디케이터 커스텀 빌더 |
| `headerBuilder` | `Widget Function(BuildContext)?` | 선택 | `null` | 메시지 목록 상단 헤더 빌더 |
| `footerBuilder` | `Widget Function(BuildContext)?` | 선택 | `null` | 메시지 목록과 입력창 사이 푸터 빌더 |
| `onVoicePressed` | `VoidCallback?` | 선택 | `null` | 음성 입력 버튼 클릭 콜백 |
| `onTapMessage` | `void Function(AdkChatMessage)?` | 선택 | `null` | 메시지 버블 클릭 콜백 |
| `onLongPressMessage`| `void Function(AdkChatMessage)?`| 선택 | `null` | 메시지 버블 롱프레스 콜백 |
| `showAppBar` | `bool` | 선택 | `false` | 내부 AppBar 표시 여부 |
| `showAvatars` | `bool?` | 선택 | `null` | 아바타 표시 여부 |

---

### `AdkDevStudioView`
`adk web`의 전체 기능을 Flutter 내부에서 즉시 실행할 수 있는 통합 개발자 스튜디오입니다.
1. **Playground**: 라이브 모델 대화창
2. **Logger**: 에이전트 I/O, 레이턴시, 토큰 메트릭 및 JSON 내보내기
3. **Agent Graph**: 서브 에이전트 및 도구 의존성 트리 뷰
4. **State**: 세션 상태 변수 실시간 인스펙터

- **파일**: [`adk_dev_studio_view.dart`](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/packages/flutter_adk/lib/src/widgets/adk_dev_studio_view.dart)

#### 파라미터 명세

| 파라미터 | 타입 | 필수 여부 | 기본값 | 설명 |
| :--- | :--- | :---: | :--- | :--- |
| `agent` | `BaseAgent?` | 선택 | `null` | 분석 및 실행할 에이전트 |
| `runner` | `Runner?` | 선택 | `null` | 런타임 러너 |
| `controller` | `AdkChatController?` | 선택 | `null` | 챗 컨트롤러 |
| `title` | `String` | 선택 | `'ADK Dev Studio'` | 스튜디오 헤더 타이틀 |
| `initialTabIndex` | `int` | 선택 | `0` | 초기 활성 탭 (0: Playground, 1: Logger, 2: Graph, 3: State) |
| `initialState` | `Map<String, dynamic>`| 선택 | `{}` | State 인스펙터 초기 세션 상태 |
| `suggestions` | `List<String>` | 선택 | 3개 프리셋 | 플레이그라운드 테스트용 추천 프롬프트 |

---

### `AdkSplitPaneView`
웹/데스크톱/태블릿 환경에 최적화된 화면 분할 레이아웃입니다. 좌측에는 대화창, 우측 탭에는 도구 인스펙터 및 로그를 배치하며, 모바일 폭 이하로 축소 시 단일 화면으로 자동 반응 전환됩니다.

- **파일**: [`adk_split_pane_view.dart`](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/packages/flutter_adk/lib/src/widgets/adk_split_pane_view.dart)

#### 파라미터 명세

| 파라미터 | 타입 | 필수 여부 | 기본값 | 설명 |
| :--- | :--- | :---: | :--- | :--- |
| `splitRatio` | `double` | 선택 | `0.55` | 좌측 대화창 분할 비율 (0.1 ~ 0.9) |
| `breakpoint` | `double` | 선택 | `768.0` | 단일 창 모드로 접히는 화면 너비 기준값 |
| `dividerColor` | `Color?` | 선택 | 테마 outline | 수직 분할선 색상 |
| `dividerWidth` | `double` | 선택 | `1.0` | 분할선 두께 |
| `showToolInspector`| `bool` | 선택 | `true` | 우측 도구 인스펙터 탭 포함 여부 |
| `showLogger` | `bool` | 선택 | `true` | 우측 실시간 로거 탭 포함 여부 |
| `customRightTabs` | `List<Tab>` | 선택 | `const []` | 사용자 정의 우측 추가 탭 |
| `customRightViews`| `List<Widget>` | 선택 | `const []` | 추가 탭에 대응하는 위젯 뷰 |

---

### `AdkAgentManagementView`
다중 에이전트 플릿(Fleet) 관리 대시보드입니다. 에이전트별 활성화(ON/OFF) 토글, 프롬프트 실시간 검사, 레이턴시/토큰 원격 측정 데이터를 요약 제공합니다.

- **파일**: [`adk_agent_management_view.dart`](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/packages/flutter_adk/lib/src/widgets/adk_agent_management_view.dart)

---

### `AdkSmartFormView`
사용자와의 자연스러운 대화를 통해 구조화된 양식 필드(JSON)를 자동으로 수집하고 검증한 후 제출하는 대화형 폼 위젯입니다.

- **파일**: [`adk_smart_form_view.dart`](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/packages/flutter_adk/lib/src/widgets/adk_smart_form_view.dart)

---

### `AdkAgentLoggerView`
실시간 I/O 및 텔레메트리 로거입니다. 카테고리 필터(`all`, `prompt`, `response`, `toolCall`, `error`, `system`), 텍스트 검색, 포맷팅된 JSON 내보내기/복사 기능을 제공합니다.

- **파일**: [`adk_agent_logger_view.dart`](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/packages/flutter_adk/lib/src/widgets/adk_agent_logger_view.dart)

---

### `AdkToolInspectorView`
에이전트에 등록된 모든 툴 선언과 파라미터 스키마(타입, 필수값 여부, 설명)를 트리 뷰로 시각화합니다.

- **파일**: [`adk_tool_inspector_view.dart`](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/packages/flutter_adk/lib/src/widgets/adk_tool_inspector_view.dart)

---

### `AdkArtifactViewer` 및 `AdkArtifactCard`
에이전트가 생성한 아티팩트(마크다운, 코드, 텍스트, 구조화 데이터)를 전용 뷰어로 표시하고 복사 및 다운로드 기능을 제공합니다.

- **파일**: [`adk_artifact_viewer.dart`](file:///Users/jaichang/Documents/GitHub/adk-labs/adk-dart/adk_dart/packages/flutter_adk/lib/src/widgets/adk_artifact_viewer.dart)

---

## 3. 모달, 드로어 및 플로팅 위젯

- **`showAdkChatBottomSheet`**: 기존 모바일 화면 위에 드래그 가능한 모달 바텀 시트로 `AdkChatView`를 띄웁니다.
- **`AdkFloatingChatButton`**: 클릭 시 대화 모달 바텀 시트를 호출하는 플로팅 액션 버튼(FAB)입니다.
- **`AdkSessionDrawer`**: 대화 세션 목록 조회, 전환, 신규 생성(`+`), 삭제 기능을 제공하는 사이드 드로어입니다.

---

## 4. 대화 피드 및 메시지 컴포넌트

- **`AdkMessageBubble`**: 역할(`user`, `model`, `tool`, `system`)별 스타일, 마크다운 렌더링, 코드 실행 카드 및 출처 칩이 결합된 종합 메시지 버블입니다.
- **`AdkTypingIndicator`**: 모델 응답 생성 중 표시되는 부드러운 3점 펄스 애니메이션입니다.
- **`AdkReasoningExpander`**: Gemini 3.7 Thinking / Claude 3.7의 사고 과정을 접고 펼칠 수 있는 아코디언 컴포넌트입니다.
- **`AdkPromptSuggestionsBar`**: 사용자가 원클릭으로 보낼 수 있는 추천 프롬프트 칩 바입니다.
- **`AdkInlineAssistantBar`**: 텍스트 입력 필드 위에 부착하여 문법 교정, 문장 다듬기, 요약, 번역을 한 번에 실행하는 코파일럿 툴바입니다.

---

## 5. 도구 실행, 코드 및 검색 출처

- **`AdkToolCallCard`**: 도구 이름, 호출 ID, 파라미터 JSON, 실행 상태(`pending`, `running`, `success`, `error`), 반환값을 표시하는 아코디언 카드입니다.
- **`AdkCodeExecutionCard`**: 샌드박스에서 실행된 Python 또는 Shell 코드, 구문 하이라이트 박스, stdout/stderr 출력 패널, 원클릭 복사 버튼을 제공합니다.
- **`AdkGroundingSourcesBar`**: Google Search Grounding 또는 Vertex Search에서 인용된 출처 링크와 검색 쿼리 칩을 렌더링합니다.
- **`AdkStructuredDataView`**: 구조화된 출력(JSON / Map)을 트리 구조로 포맷팅하여 표시합니다.

---

## 6. Human-in-the-Loop 및 실행 인터럽트

### `AdkInterruptBanner`
긴 툴 실행 중 사용자 승인 또는 입력이 필요하여 런타임이 일시 중지되었을 때 표시되는 알림 배너입니다.

#### 파라미터 명세

| 파라미터 | 타입 | 필수 여부 | 기본값 | 설명 |
| :--- | :--- | :---: | :--- | :--- |
| `toolName` | `String` | **필수** | - | 일시정지를 유발한 도구 이름 |
| `reason` | `String?` | 선택 | `null` | 사용자에게 표시할 안내 사유 |
| `interruptId` | `String?` | 선택 | `null` | 고유 인터럽트 ID |
| `onResume` | `VoidCallback?` | 선택 | `null` | 재개 액션 버튼 클릭 콜백 |
| `onDismiss` | `VoidCallback?` | 선택 | `null` | 배너 닫기 콜백 |
| `actionLabel` | `String` | 선택 | `'Review & Resume'` | 액션 버튼 텍스트 |
| `backgroundColor`| `Color?` | 선택 | 테마 errorContainer | 배너 배경색 |
| `foregroundColor`| `Color?` | 선택 | 테마 onErrorContainer | 텍스트 및 아이콘 색상 |
| `icon` | `IconData?` | 선택 | `Icons.pause_circle_filled_rounded` | 리딩 아이콘 |
| `borderRadius` | `BorderRadius?`| 선택 | `BorderRadius.circular(12.0)` | 테두리 둥글기 |
| `padding` | `EdgeInsetsGeometry?`| 선택 | `symmetric(h: 14, v: 10)` | 내부 여백 |
| `margin` | `EdgeInsetsGeometry?`| 선택 | `symmetric(h: 12, v: 6)` | 외부 여백 |
| `actionBuilder` | `Widget Function(BuildContext, VoidCallback?)?` | 선택 | `null` | 액션 버튼 영역 커스텀 빌더 |

---

### `AdkInterruptCard`
일시정지된 툴의 파라미터 JSON 미리보기, 사용자 추가 입력 필드, Resume / Cancel 버튼을 제공하는 대화형 카드입니다.

#### 파라미터 명세

| 파라미터 | 타입 | 필수 여부 | 기본값 | 설명 |
| :--- | :--- | :---: | :--- | :--- |
| `toolName` | `String` | **필수** | - | 일시정지된 도구 이름 |
| `interruptId` | `String?` | 선택 | `null` | 고유 인터럽트 식별자 |
| `arguments` | `Map<String, dynamic>?` | 선택 | `null` | 도구 호출 시 전달된 파라미터 맵 |
| `reason` | `String?` | 선택 | `null` | 인터럽트 발생 사유 |
| `requiresInput` | `bool` | 선택 | `false` | 재개를 위해 텍스트 입력이 필요한지 여부 |
| `inputPlaceholder` | `String` | 선택 | `'Enter required input...'` | 입력창 힌트 |
| `isProcessing` | `bool` | 선택 | `false` | 재개 처리 중 로딩 상태 표시 |
| `onResume` | `void Function(String? inputValue)?` | 선택 | `null` | 재개 시 사용자 입력을 전달하는 콜백 |
| `onCancel` | `VoidCallback?` | 선택 | `null` | 취소 콜백 |
| `cardElevation` | `double` | 선택 | `2.0` | 카드 그림자 높이 |
| `borderRadius` | `BorderRadius?` | 선택 | `BorderRadius.circular(14.0)` | 카드 둥글기 |
| `accentColor` | `Color?` | 선택 | 테마 error 색상 | 강조 색상 (아이콘 및 테두리) |
| `headerBuilder` | `Widget Function(BuildContext)?` | 선택 | `null` | 카드 헤더 커스텀 빌더 |
| `actionsBuilder` | `Widget Function(BuildContext, void Function(String?)?, VoidCallback?, bool)?` | 선택 | `null` | 액션 버튼 커스텀 빌더 |
| `inputDecoration`| `InputDecoration?` | 선택 | `null` | 입력창 데코레이션 커스텀 오버라이드 |

---

### `AdkConfirmationBanner` 및 `AdkConfirmationDialog`
민감한 권한(송금, 파일 삭제 등) 실행 전 확인을 요청하는 인라인 배너 및 모달 다이얼로그(`showAsDialog`)입니다.

---

### `AdkHumanInTheLoopCard`
대화 스트림 내부에서 승인(`Approve`), 거부(`Reject`), 수정(`Modify`)을 수행할 수 있는 체크포인트 카드입니다.

---

## 7. 실시간 멀티모달 및 음성 스트리밍

### `AdkCascadeLiveBar`
`CascadeLive` 및 Gemini Live API 음성 대화 세션을 위한 실시간 스트리밍 컨트롤 바입니다. 실시간 STT 자막, 음성 파형 애니메이션, 마이크 토글, 사용자 끼어들기(Barge-in) 뱃지를 지원합니다.

#### 파라미터 명세

| 파라미터 | 타입 | 필수 여부 | 기본값 | 설명 |
| :--- | :--- | :---: | :--- | :--- |
| `isListening` | `bool` | **필수** | - | 마이크 오디오 전송 중 여부 |
| `isSpeaking` | `bool` | 선택 | `false` | 에이전트 음성 출력 재생 중 여부 |
| `isBargeIn` | `bool` | 선택 | `false` | 사용자 끼어들기 발생 여부 |
| `partialTranscript` | `String?` | 선택 | `null` | STT 실시간 자막 문자열 |
| `onMicToggle` | `VoidCallback?` | 선택 | `null` | 마이크 버튼 클릭 콜백 |
| `onDisconnect` | `VoidCallback?` | 선택 | `null` | 통화 종료 버튼 클릭 콜백 |
| `statusText` | `String?` | 선택 | `null` | 커스텀 상태 텍스트 |
| `backgroundColor` | `Color?` | 선택 | 테마 surfaceContainerHigh | 바 배경색 |
| `visualizerColor` | `Color?` | 선택 | 테마 primary / secondary | 파형 바 색상 |
| `bargeInColor` | `Color?` | 선택 | 테마 error | 끼어들기 발생 시 강조 색상 |
| `elevation` | `double?` | 선택 | `10.0` | 그림자 블러 반경 |
| `margin` | `EdgeInsetsGeometry?`| 선택 | `EdgeInsets.all(12.0)` | 외부 여백 |
| `padding` | `EdgeInsetsGeometry?`| 선택 | `symmetric(h: 16, v: 10)` | 내부 여백 |
| `borderRadius` | `BorderRadius?`| 선택 | `BorderRadius.circular(28.0)` | 모서리 둥글기 |
| `customLeading` | `Widget?` | 선택 | `null` | 마이크 버튼 교체용 커스텀 위젯 |
| `customTrailing` | `Widget?` | 선택 | `null` | 종료 버튼 교체용 커스텀 위젯 |
| `waveVisualizerBuilder`| `Widget Function(BuildContext, bool, bool, bool)?`| 선택 | `null` | 파형 시각화 커스텀 빌더 |

---

### `AdkLiveBargeInIndicator`
모델이 발화 중일 때 사용자가 말을 시작하여 모델 발화가 중단되었음을 알려주는 페이드 애니메이션 뱃지입니다.

---

### `AdkVoiceMicButton` 및 `AdkAudioWaveVisualizer`
- **`AdkVoiceMicButton`**: 청취 중일 때 부드러운 링 펄스 애니메이션이 동작하는 마이크 버튼입니다.
- **`AdkAudioWaveVisualizer`**: 음성 데시벨 및 활성 상태에 반응하는 멀티 바 오디오 파형 위젯입니다.

---

## 8. 워크플로우, 라우팅 및 다중 모델 시각화

### `AdkWorkflowGraphView`
ADK `Workflow` 및 `EdgesBuilder` 파이프라인의 실행 상태를 시각화하는 플로우차트 / DAG 그래프 뷰어입니다. 가로 및 세로 배치를 모두 지원합니다.

#### 파라미터 명세

| 파라미터 | 타입 | 필수 여부 | 기본값 | 설명 |
| :--- | :--- | :---: | :--- | :--- |
| `nodes` | `List<AdkGraphNode>` | **필수** | - | 순차 또는 토폴로지 순서의 노드 목록 |
| `edges` | `List<AdkGraphEdge>` | 선택 | `const []` | 분기 라벨이 포함된 유향 엣지 목록 |
| `onNodeTap` | `void Function(AdkGraphNode)?` | 선택 | `null` | 노드 클릭 시 콜백 |
| `activeNodeId` | `String?` | 선택 | `null` | 현재 활성/강조할 노드 ID |
| `title` | `String` | 선택 | `'Workflow Execution Graph'` | 헤더 제목 |
| `orientation` | `Axis` | 선택 | `Axis.horizontal` | 배치 방향 (`Axis.horizontal` 또는 `Axis.vertical`) |
| `nodeWidth` | `double` | 선택 | `140.0` | 기본 노드 카드 너비 |
| `nodeHeight` | `double?` | 선택 | `null` | 기본 노드 카드 높이 |
| `cardElevation` | `double` | 선택 | `2.0` | 외곽 카드 그림자 높이 |
| `borderRadius` | `BorderRadius?` | 선택 | `BorderRadius.circular(16.0)` | 카드 모서리 둥글기 |
| `cardMargin` | `EdgeInsetsGeometry?`| 선택 | `symmetric(h: 12, v: 8)` | 카드 외부 여백 |
| `cardPadding` | `EdgeInsetsGeometry?`| 선택 | `EdgeInsets.all(16.0)` | 카드 내부 여백 |
| `completedColor`| `Color?` | 선택 | 녹색 (`#388E3C`) | 완료 상태 노드 색상 |
| `runningColor` | `Color?` | 선택 | 테마 primary | 실행 중 노드 색상 |
| `failedColor` | `Color?` | 선택 | 테마 error | 실패 노드 색상 |
| `skippedColor` | `Color?` | 선택 | 테마 outline | 건너뛴 노드 색상 |
| `pendingColor` | `Color?` | 선택 | 테마 outlineVariant | 대기 노드 색상 |
| `activeBorderColor`| `Color?` | 선택 | 테마 primary | 활성 노드 테두리 강조 색상 |
| `nodeBuilder` | `Widget Function(BuildContext, AdkGraphNode, bool, AdkGraphNodeStatus, VoidCallback?)?` | 선택 | `null` | 노드 카드 커스텀 빌더 |
| `edgeBuilder` | `Widget Function(BuildContext, AdkGraphEdge?, bool)?` | 선택 | `null` | 엣지 연결선 커스텀 빌더 |

---

### `AdkClassifierCard`
ADK `ClassifierNode`가 결정한 분기 경로, 신뢰도 점수, 후보 경로별 확률 분포를 표시합니다.

#### 파라미터 명세

| 파라미터 | 타입 | 필수 여부 | 기본값 | 설명 |
| :--- | :--- | :---: | :--- | :--- |
| `selectedRoute` | `String` | **필수** | - | 분류기가 선택한 경로 |
| `question` | `String?` | 선택 | `null` | 분류 지침 또는 프롬프트 |
| `confidence` | `double?` | 선택 | `null` | 전체 신뢰도 점수 (0.0 ~ 1.0) |
| `probabilities` | `Map<String, double>` | 선택 | `{}` | 후보 경로별 확률 맵 |
| `title` | `String` | 선택 | `'Workflow Classification'` | 카드 제목 |
| `onRouteSelected`| `void Function(String)?` | 선택 | `null` | 후보 경로 탭 콜백 |
| `cardElevation` | `double` | 선택 | `1.5` | 카드 그림자 높이 |
| `borderRadius` | `BorderRadius?` | 선택 | `BorderRadius.circular(14.0)` | 카드 테두리 둥글기 |
| `routeChipColor`| `Color?` | 선택 | 테마 primaryContainer | 선택된 경로 칩 배경색 |
| `routeChipTextColor`| `Color?`| 선택 | 테마 onPrimaryContainer | 선택된 경로 칩 텍스트 색상 |
| `confidenceColorBuilder`| `Color Function(BuildContext, double?)?`| 선택 | `null` | 신뢰도 점수 색상 커스텀 콜백 |
| `probabilityBarColorBuilder`| `Color Function(BuildContext, String, double, bool)?`| 선택 | `null` | 확률 게이지 바 색상 커스텀 콜백 |
| `customRouteTileBuilder`| `Widget Function(BuildContext, String, double, bool, VoidCallback?)?`| 선택 | `null` | 개별 후보 타일 커스텀 빌더 |

---

### `AdkModelConsultBadge` 및 `AdkEscalationCard`
- **`AdkModelConsultBadge`**: 상위 어드바이저 모델(Gemini Pro 등) 상담 여부와 남은 턴 예산을 간결하게 보여주는 상태 칩입니다.
- **`AdkEscalationCard`**: 어드바이저 모델 응답, 상담 사유, 턴 및 세션 예산 게이지 바를 보여주는 확장형 카드입니다 (`headerBuilder`, `contentBuilder` 제공).

---

### `AdkWorkflowProgressIndicator`
선형 워크플로우 진행 단계를 순차적으로 표시하는 타임라인 진행률 바입니다.

---

### `AdkAgentHierarchyBadge`
계층형 멀티 에이전트 구조에서 현재 위임된 에이전트 경로(예: `슈퍼바이저 > 리서처 > 팩트체커`)를 브레드크럼 형태로 표시합니다.

---

### `AdkAgentPersonaSelector`
사용자가 원하는 에이전트 페르소나를 빠르게 선택할 수 있는 그리드/캐러셀 선택기입니다.

---

## 9. 원격 측정 및 반응형 스트림 빌더

### `AdkTokenUsageBadge`
프롬프트, 컴플리션, 캐시, 총합 토큰 사용량과 비용 툴팁을 제공하는 컴팩트 뱃지입니다. `style` (`AdkCardStyle`), `leadingIcon`, `trailingWidget`, `contentBuilder` 커스터마이징을 지원합니다.

---

### `AdkUsageMonitorCard`
세션 및 턴 단위 토큰 사용량/비용 대시보드 카드입니다. 카테고리별 비율 스택 바(`Prompt`, `Cached`, `Output`, `Thoughts`, `Tool Prompt`), 캐시 적중률(%), 평균 지연 시간, USD 예상 비용 계산기 및 초기화(`onReset`) 버튼을 제공하며 `style`, `headerBuilder`, `barBuilder`, `metricsBuilder`를 지원합니다.

---

### `AdkContextWindowMeter`
컨텍스트 윈도우 점유율(`usedTokens / maxContextTokens`) 진행률 게이지 및 컴팩션 임계치(`compactionThresholdTokens`) 수직 마커 위젯입니다. 컴팩트/전체 모드와 점유율 구간별 색상(`normalColor`, `warningColor`, `criticalColor`) 자동 전환을 지원합니다.

---

### `AdkSkillToolCard`
`SkillToolset` (`list_skills`, `search_skills`, `load_skill`, `unload_skill`, `load_skill_resource`) 호출 전용 카드 위젯으로, `<available_skills>` XML 목록을 파싱하여 스킬 배지로 시각화하고 `SKILL.md` 본문 및 리소스를 표시합니다.

---

### `AdkFileEditCard`
`EnvironmentToolset` 파일 도구(`EditFile`, `WriteFile`, `ReadFile`) 전용 카드 위젯으로, LCS 알고리즘 기반 줄 단위 Unified Diff 뷰어(`AdkDiffLine`)와 원클릭 복사 기능을 제공합니다.

---

### `AdkShellCommandCard`
셸 명령어 및 스킬 스크립트(`Execute`, `execute_bash`, `run_command`, `run_skill_script`) 실행 결과를 다크 터미널 테마로 표시하는 카드입니다. ANSI 이스케이프 코드 자동 제거, `stdout`/`stderr` 분리 표시, `exit_code` 및 타임아웃 배지를 제공합니다.

---

### `AdkWebPageCard`
`load_web_page` / `fetch_web_page` 도구 호출 전용 카드로, 대상 URL, 도메인 배지, 본문 미리보기 접기/펴기 및 에러 상태를 표시합니다.

---

### `AdkComputerActionCard`
`ComputerUseToolset` (`click_at`, `type_text_at`, `scroll_at`, `navigate` 등) 브라우저/데스크톱 제어 액션을 시각화하는 카드로, `(x, y)` 좌표 배지, 입력 텍스트, Base64 스크린샷 렌더링을 지원합니다.

---

### `AdkCompactionSummaryCard`
대화 히스토리 컴팩션(`EventActions.compaction`) 이벤트를 타임라인 배너/아코디언 형태로 표시하는 카드 위젯입니다.

---

### `AdkReflectRetryBanner`
`ReflectAndRetryToolPlugin` / `ReflectAndRetryModelPlugin`의 자기 치유(Self-healing) 재시도 상태(`Attempt N/M`)와 리플렉션 가이드를 표시하는 배너 위젯입니다.

---

### `AdkMultiRunEvalCard`
멀티 런 평가 결과(`MultiRunCaseResult`, `AdkMultiRunEvalCard.fromCoreResults`)의 전체 통과율, 메트릭별 평균 점수 및 표준편차(`±σ`), 케이스별 통과 비율을 집계하여 보여주는 카드입니다.

---

### `AdkEventStreamBuilder`
`runner.runAsync(...)`에서 반환되는 ADK `Stream<Event>`를 직접 구독하여 실시간 이벤트 발생 시 UI를 다시 빌드하는 반응형 위젯입니다.

```dart
AdkEventStreamBuilder(
  stream: runner.runAsync(agent: myAgent, prompt: '데이터 분석해줘'),
  builder: (context, List<Event> events, bool isCompleted) {
    if (events.isEmpty) return const CircularProgressIndicator();
    return ListView(children: events.map((e) => Text(e.stringify())).toList());
  },
)
```

---

## 10. ADK UI 유틸리티

`flutter_adk.dart`에서 즉시 사용 가능한 3가지 핵심 헬퍼 클래스 명세입니다:

```dart
// 1. AdkFormatters: 토큰, 시간, 바이트, JSON 문자열 변환
static String AdkFormatters.formatTokens(int tokens, {bool compact = false});
static String AdkFormatters.formatDuration(Duration duration);
static String AdkFormatters.formatBytes(int bytes);
static String AdkFormatters.formatJson(Object? data);

// 2. AdkEventStreamUtils: 이벤트 스트림에서 오픈 인터럽트, 툴 호출, 토큰 메트릭 추출
static Map<String, OpenInterrupt> AdkEventStreamUtils.extractOpenInterrupts(List<Event> events);
static bool AdkEventStreamUtils.hasOpenInterrupts(List<Event> events);
static List<AdkToolCallInfo> AdkEventStreamUtils.extractToolCalls(Event event);
static AdkTokenUsage? AdkEventStreamUtils.extractTokenUsage(Event event);
static bool AdkEventStreamUtils.isModelConsultEvent(Event event);
static ({String? advisorModel, String? escalationReason, int? turnCount, int? turnBudget})
    AdkEventStreamUtils.extractModelConsultInfo(Event event);

// 3. AdkColorUtils: Material 3 테마 호환 신뢰도 및 워크플로우 상태 색상 결정
static Color AdkColorUtils.confidenceColor(BuildContext context, double confidence);
static Color AdkColorUtils.nodeStatusColor(BuildContext context, AdkGraphNodeStatus status);
```

---

## 11. 테마 시스템 (AdkTheme & AdkChatThemeData)

위젯 서브트리를 `AdkTheme`으로 감싸면 전체 위젯에 전역 디자인 토큰이 적용됩니다:

```dart
AdkTheme(
  data: const AdkChatThemeData(
    userBubbleColor: Color(0xFF1E88E5),
    modelBubbleColor: Color(0xFFF5F5F5),
    userTextColor: Colors.white,
    modelTextColor: Colors.black87,
    borderRadius: BorderRadius.all(Radius.circular(18.0)),
    inputBackgroundColor: Colors.white,
    sendButtonColor: Color(0xFF1E88E5),
    showTimestamp: true,
    showAvatars: true,
  ),
  child: AdkChatView(agent: myAgent),
)
```
