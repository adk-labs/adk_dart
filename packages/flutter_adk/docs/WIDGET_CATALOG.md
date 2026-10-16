# Flutter ADK Widget & Utilities Catalog

`flutter_adk` provides a comprehensive suite of production-grade Flutter widgets, controllers, and utility helpers specifically designed for building conversational AI agents, multimodal live streaming voice assistants, Human-in-the-Loop (HITL) workflows, and multi-model escalation architectures powered by Google ADK.

All widgets adhere to Material 3 design principles, fully adapt to light/dark themes, and provide extensive customization hooks (colors, borders, paddings, elevations, icons, and builder callbacks).

---

## Table of Contents

1. [Quick Import](#quick-import)
2. [Interactive HITL & Interrupt Widgets](#1-interactive-hitl--interrupt-widgets)
   - [AdkInterruptBanner](#adkinterruptbanner)
   - [AdkInterruptCard](#adkinterruptcard)
3. [Real-Time Multimodal & Voice Streaming](#2-real-time-multimodal--voice-streaming)
   - [AdkCascadeLiveBar](#adkcascadelivebar)
   - [AdkLiveBargeInIndicator](#adklivebargeinindicator)
4. [Multi-Model Orchestration & Escalation](#3-multi-model-orchestration--escalation)
   - [AdkModelConsultBadge](#adkmodelconsultbadge)
   - [AdkEscalationCard](#adkescalationcard)
5. [Dynamic Routing & Workflow Classifiers](#4-dynamic-routing--workflow-classifiers)
   - [AdkClassifierCard](#adkclassifiercard)
6. [Workflow Flowchart & Execution Graphs](#5-workflow-flowchart--execution-graphs)
   - [AdkWorkflowGraphView](#adkworkflowgraphview)
7. [ADK UI Utilities](#6-adk-ui-utilities)
   - [AdkFormatters](#adkformatters)
   - [AdkEventStreamUtils](#adkeventstreamutils)
   - [AdkColorUtils](#adkcolorutils)
8. [Copy-Paste Recipes](#7-copy-paste-recipes)

---

## Quick Import

All widgets, models, controllers, and utilities are exported through the single top-level library:

```dart
import 'package:flutter_adk/flutter_adk.dart';
```

---

## 1. Interactive HITL & Interrupt Widgets

When an agent tool or workflow node requires explicit user confirmation or external input (e.g. OTP validation, dangerous actions, high-value payments), the runtime emits an open interrupt.

### `AdkInterruptBanner`

A notification banner displayed at the top or bottom of a chat view or screen when an execution pause is detected.

#### Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `toolName` | `String` | **Required** | Name of the tool or node triggering the interrupt. |
| `reason` | `String?` | `null` | High-level explanation or prompt for the user. |
| `interruptId` | `String?` | `null` | Unique identifier of the interrupt. |
| `onResume` | `VoidCallback?` | `null` | Callback triggered when the user clicks the resume action button. |
| `onDismiss` | `VoidCallback?` | `null` | Callback triggered when the user dismisses the banner. |
| `actionLabel` | `String` | `'Review & Resume'` | Label on the default action button. |
| `backgroundColor`| `Color?` | Theme errorContainer | Custom background container color. |
| `foregroundColor`| `Color?` | Theme onErrorContainer| Custom text and icon color. |
| `icon` | `IconData?` | `Icons.pause_circle_filled_rounded` | Custom leading icon. |
| `borderRadius` | `BorderRadius?`| `BorderRadius.circular(12.0)` | Corner border radius. |
| `padding` | `EdgeInsetsGeometry?` | `symmetric(h: 14, v: 10)` | Container padding. |
| `margin` | `EdgeInsetsGeometry?` | `symmetric(h: 12, v: 6)` | Outer margin. |
| `actionBuilder` | `Widget Function(BuildContext, VoidCallback?)?` | `null` | Custom builder to completely replace the action button. |

#### Usage Example

```dart
AdkInterruptBanner(
  toolName: 'execute_payment',
  reason: 'Transfer of \$500.00 to Alice requires authorization.',
  onResume: () => showPaymentApprovalDialog(context),
  onDismiss: () => dismissNotification(),
)
```

#### Customization with `actionBuilder`

```dart
AdkInterruptBanner(
  toolName: 'deploy_production',
  backgroundColor: Colors.amber.shade900,
  foregroundColor: Colors.white,
  icon: Icons.warning_amber_rounded,
  actionBuilder: (context, onResume) => ElevatedButton.icon(
    onPressed: onResume,
    icon: const Icon(Icons.lock_open, size: 16),
    label: const Text('Authorize Now'),
    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
  ),
)
```

---

### `AdkInterruptCard`

An interactive card widget detailing a paused interrupt with parameter JSON previews, an optional text input field, and confirmation/cancellation buttons.

#### Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `toolName` | `String` | **Required** | The name of the tool causing the pause. |
| `interruptId` | `String?` | `null` | Unique interrupt identifier. |
| `arguments` | `Map<String, dynamic>?` | `null` | Parameter arguments passed to the tool call. |
| `reason` | `String?` | `null` | Explanation for why the interrupt occurred. |
| `requiresInput` | `bool` | `false` | Whether the user must provide text input before resuming. |
| `inputPlaceholder` | `String` | `'Enter required input...'` | Placeholder hint for the input field. |
| `isProcessing` | `bool` | `false` | Shows a loading indicator on the resume button when true. |
| `onResume` | `void Function(String? inputValue)?` | `null` | Callback when the user confirms or submits input. |
| `onCancel` | `VoidCallback?` | `null` | Callback when the user cancels the operation. |
| `cardElevation` | `double` | `2.0` | Elevation shadow of the card. |
| `borderRadius` | `BorderRadius?` | `BorderRadius.circular(14.0)` | Corner border radius. |
| `accentColor` | `Color?` | Theme error color | Accent color for borders and icons. |
| `headerBuilder` | `Widget Function(BuildContext)?` | `null` | Custom builder replacing the card header row. |
| `actionsBuilder` | `Widget Function(BuildContext, void Function(String?)?, VoidCallback?, bool)?` | `null` | Custom builder for action buttons. |
| `inputDecoration`| `InputDecoration?` | `null` | Custom decoration for the text input field. |

#### Usage Example

```dart
AdkInterruptCard(
  toolName: 'verify_2fa',
  interruptId: 'auth_step_2',
  requiresInput: true,
  inputPlaceholder: 'Enter 6-digit SMS code',
  arguments: const <String, dynamic>{'phone': '+1 (555) 019-2834'},
  reason: 'A confirmation code has been sent to your device.',
  onResume: (code) {
    runner.resume(resumeInputs: {'auth_step_2': code});
  },
  onCancel: () => cancelOperation(),
)
```

---

## 2. Real-Time Multimodal & Voice Streaming

`CascadeLive` and Gemini Live API streaming allow voice-to-voice bidirectional communication with automatic speech detection (VAD) and barge-in (user speech interrupting model speech).

### `AdkCascadeLiveBar`

A floating or docked bottom bar for speech-driven interactions with live waveform visualization, microphone toggling, barge-in indicators, and real-time STT transcripts.

#### Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `isListening` | `bool` | **Required** | Whether user microphone is actively streaming audio. |
| `isSpeaking` | `bool` | `false` | Whether agent TTS is playing audio to the user. |
| `isBargeIn` | `bool` | `false` | Whether user speech interrupted the agent. |
| `partialTranscript` | `String?` | `null` | Real-time live transcript from STT. |
| `onMicToggle` | `VoidCallback?` | `null` | Tap callback for the microphone button. |
| `onDisconnect` | `VoidCallback?` | `null` | Tap callback for ending the live call. |
| `statusText` | `String?` | `null` | Overrides default status text ('Listening...', etc.). |
| `backgroundColor` | `Color?` | Theme surfaceContainerHigh | Container background color. |
| `visualizerColor` | `Color?` | Theme primary / secondary | Waveform bars color. |
| `bargeInColor` | `Color?` | Theme error | Color applied during barge-in interrupts. |
| `elevation` | `double?` | `10.0` | Shadow elevation blur radius. |
| `margin` | `EdgeInsetsGeometry?` | `EdgeInsets.all(12.0)` | Outer margin. |
| `padding` | `EdgeInsetsGeometry?` | `symmetric(h: 16, v: 10)` | Inner padding. |
| `borderRadius` | `BorderRadius?` | `BorderRadius.circular(28.0)` | Corner radius. |
| `customLeading` | `Widget?` | `null` | Custom widget replacing the default microphone button. |
| `customTrailing` | `Widget?` | `null` | Custom widget replacing the default disconnect button. |
| `waveVisualizerBuilder` | `Widget Function(BuildContext, bool, bool, bool)?` | `null` | Custom waveform visualizer builder. |

#### Usage Example

```dart
AdkCascadeLiveBar(
  isListening: liveController.isListening,
  isSpeaking: liveController.isSpeaking,
  isBargeIn: liveController.isBargeIn,
  partialTranscript: liveController.currentTranscript,
  onMicToggle: () => liveController.toggleMic(),
  onDisconnect: () => liveController.disconnect(),
)
```

---

### `AdkLiveBargeInIndicator`

An animated reactive badge that smoothly fades in when the user interrupts agent speech (barge-in event).

#### Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `isBargeIn` | `bool` | **Required** | Whether barge-in interruption is active. |
| `label` | `String` | `'Agent Interrupted'` | Text label inside the badge. |
| `backgroundColor` | `Color?` | Theme errorContainer | Badge background color. |
| `textColor` | `Color?` | Theme onErrorContainer | Badge text color. |
| `iconColor` | `Color?` | Theme error | Lightning icon color. |
| `icon` | `IconData?` | `Icons.bolt_rounded` | Badge icon. |
| `borderRadius` | `BorderRadius?` | `BorderRadius.circular(16.0)` | Border radius. |
| `padding` | `EdgeInsetsGeometry?` | `symmetric(h: 10, v: 4)` | Badge padding. |

---

## 3. Multi-Model Orchestration & Escalation

When using ADK's `ConsultModelTool` or `ForceEscalationPlugin`, a primary agent (e.g. lightweight Gemini Flash) consults a deeper reasoning model (e.g. Gemini 2.5 Pro or Thinking model) for high-complexity sub-tasks within a specified budget.

### `AdkModelConsultBadge`

A compact, clickable status chip showing which advisor model was consulted and the remaining budget.

#### Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `advisorModel` | `String` | **Required** | Model name consulted (e.g., `'gemini-2.5-pro'`). |
| `escalationReason`| `String?`| `null` | Rationale for escalation (shown in tooltip). |
| `turnCount` | `int?` | `null` | Turns used so far in this consultation budget. |
| `turnBudget` | `int?` | `null` | Maximum allowed turns for consultation. |
| `onTap` | `VoidCallback?` | `null` | Callback when tapped. |
| `backgroundColor` | `Color?` | Theme secondaryContainer | Background color. |
| `textColor` | `Color?` | Theme onSecondaryContainer| Text and icon color. |
| `borderColor` | `Color?` | Theme secondary with alpha | Border outline color. |
| `icon` | `IconData?` | `Icons.psychology_outlined` | Leading icon. |
| `borderRadius` | `BorderRadius?` | `BorderRadius.circular(16.0)` | Corner border radius. |
| `padding` | `EdgeInsetsGeometry?` | `symmetric(h: 10, v: 4)` | Inner padding. |

---

### `AdkEscalationCard`

A collapsible inspector card showing advisor reasoning, response output, and animated linear progress bars for turn and session budget tracking.

#### Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `advisorModel` | `String` | **Required** | Advisor model consulted. |
| `escalationReason`| `String` | **Required** | Trigger rationale. |
| `consultationOutput`| `String?`| `null` | Output response produced by the advisor model. |
| `turnCount` | `int` | `1` | Turns consumed. |
| `turnBudget` | `int` | `3` | Turn budget cap. |
| `sessionCount` | `int` | `1` | Session consultations consumed. |
| `sessionBudget`| `int` | `10` | Session consultation budget cap. |
| `initiallyExpanded`| `bool` | `false` | Whether initially expanded. |
| `cardElevation`| `double` | `1.0` | Card elevation. |
| `borderRadius` | `BorderRadius?` | `BorderRadius.circular(12.0)` | Card border radius. |
| `accentColor` | `Color?` | Theme secondary | Progress bar and highlight color. |
| `headerBuilder`| `Widget Function(BuildContext, bool, VoidCallback)?`| `null` | Custom header builder. |
| `contentBuilder`| `Widget Function(BuildContext)?`| `null` | Custom expanded content builder. |

---

## 4. Dynamic Routing & Workflow Classifiers

### `AdkClassifierCard`

Visualizes classifications performed by ADK's `ClassifierNode` (e.g. routing between `sales`, `support`, or `billing`), displaying overall confidence percentages and probability breakdown bars.

#### Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `selectedRoute` | `String` | **Required** | The route chosen by the classifier. |
| `question` | `String?` | `null` | Classification prompt or criteria. |
| `confidence` | `double?` | `null` | Confidence score between 0.0 and 1.0. |
| `probabilities` | `Map<String, double>` | `{}` | Candidate route probabilities. |
| `title` | `String` | `'Workflow Classification'` | Card header title. |
| `onRouteSelected`| `void Function(String)?` | `null` | Tap callback for route candidates. |
| `cardElevation` | `double` | `1.5` | Card elevation. |
| `borderRadius` | `BorderRadius?` | `BorderRadius.circular(14.0)` | Corner border radius. |
| `routeChipColor`| `Color?` | Theme primaryContainer | Selected route chip background color. |
| `routeChipTextColor`| `Color?`| Theme onPrimaryContainer| Selected route chip text color. |
| `confidenceColorBuilder`| `Color Function(BuildContext, double?)?`| `null` | Custom color callback for confidence score. |
| `probabilityBarColorBuilder`| `Color Function(BuildContext, String, double, bool)?`| `null` | Custom color callback for probability bars. |
| `customRouteTileBuilder`| `Widget Function(BuildContext, String, double, bool, VoidCallback?)?`| `null` | Custom builder for individual route tiles. |

---

## 5. Workflow Flowchart & Execution Graphs

### `AdkWorkflowGraphView`

A flowchart and execution graph viewer for ADK `Workflow` and `EdgesBuilder` pipelines. Renders nodes with their status (`pending`, `running`, `completed`, `failed`, `skipped`) and edge branch labels.

#### Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `nodes` | `List<AdkGraphNode>` | **Required** | Workflow nodes in execution or topological order. |
| `edges` | `List<AdkGraphEdge>` | `const []` | Directed edges linking nodes with branch labels. |
| `onNodeTap` | `void Function(AdkGraphNode)?` | `null` | Tap callback when a node is clicked. |
| `activeNodeId` | `String?` | `null` | ID of the active node to highlight. |
| `title` | `String` | `'Workflow Execution Graph'` | Viewer title. |
| `orientation` | `Axis` | `Axis.horizontal` | Layout direction (`Axis.horizontal` or `Axis.vertical`). |
| `nodeWidth` | `double` | `140.0` | Fixed width for default node cards. |
| `nodeHeight` | `double?` | `null` | Optional fixed height for default node cards. |
| `cardElevation` | `double` | `2.0` | Elevation shadow of the outer card. |
| `borderRadius` | `BorderRadius?` | `BorderRadius.circular(16.0)` | Corner radius. |
| `cardMargin` | `EdgeInsetsGeometry?` | `symmetric(h: 12, v: 8)` | Outer margin. |
| `cardPadding` | `EdgeInsetsGeometry?` | `EdgeInsets.all(16.0)` | Inner padding. |
| `completedColor`| `Color?` | Green (`#388E3C`) | Custom color for completed nodes. |
| `runningColor` | `Color?` | Theme primary | Custom color for running nodes. |
| `failedColor` | `Color?` | Theme error | Custom color for failed nodes. |
| `skippedColor` | `Color?` | Theme outline | Custom color for skipped nodes. |
| `pendingColor` | `Color?` | Theme outlineVariant | Custom color for pending nodes. |
| `activeBorderColor`| `Color?` | Theme primary | Custom border highlight for active node. |
| `nodeBuilder` | `Widget Function(BuildContext, AdkGraphNode, bool, AdkGraphNodeStatus, VoidCallback?)?` | `null` | Custom builder for node cards. |
| `edgeBuilder` | `Widget Function(BuildContext, AdkGraphEdge?, bool)?` | `null` | Custom builder for edge connectors. |

#### Usage Example

```dart
AdkWorkflowGraphView(
  orientation: Axis.horizontal,
  activeNodeId: 'validation_node',
  nodes: const <AdkGraphNode>[
    AdkGraphNode(id: 'start', label: 'Order Placed', status: AdkGraphNodeStatus.completed),
    AdkGraphNode(id: 'validation_node', label: 'Check Inventory', status: AdkGraphNodeStatus.running),
    AdkGraphNode(id: 'charge_card', label: 'Charge Card', status: AdkGraphNodeStatus.pending),
  ],
  edges: const <AdkGraphEdge>[
    AdkGraphEdge(fromId: 'start', toId: 'validation_node'),
    AdkGraphEdge(fromId: 'validation_node', toId: 'charge_card', label: 'in-stock'),
  ],
  onNodeTap: (node) => inspectNodeExecution(node.id),
)
```

---

## 6. ADK UI Utilities

The `AdkFormatters`, `AdkEventStreamUtils`, and `AdkColorUtils` classes provide zero-boilerplate helpers for stream parsing, formatting, and theme-compatible coloring.

### `AdkFormatters`

```dart
// Format raw token counts
AdkFormatters.formatTokens(450);                 // '450 tokens'
AdkFormatters.formatTokens(2500);                // '2.5k tokens'
AdkFormatters.formatTokens(2500, compact: true); // '2.5k'
AdkFormatters.formatTokens(1500000);             // '1.5M tokens'

// Format latencies and durations
AdkFormatters.formatDuration(Duration(milliseconds: 320)); // '320ms'
AdkFormatters.formatDuration(Duration(seconds: 4, milliseconds: 200)); // '4.20s'
AdkFormatters.formatDuration(Duration(minutes: 2, seconds: 15));       // '2m 15s'

// Format payload sizes
AdkFormatters.formatBytes(512);               // '512 B'
AdkFormatters.formatBytes(1024 * 350);        // '350.0 KB'
AdkFormatters.formatBytes(1024 * 1024 * 5);   // '5.0 MB'

// Format JSON safely
AdkFormatters.formatJson({'status': 'ready', 'code': 200});
```

### `AdkEventStreamUtils`

```dart
// Extract open unresolved interrupts from an event stream
Map<String, OpenInterrupt> interrupts = AdkEventStreamUtils.extractOpenInterrupts(eventList);
bool hasPausedTools = AdkEventStreamUtils.hasOpenInterrupts(eventList);

// Extract structured tool call turns from an Event
List<AdkToolCallInfo> toolCalls = AdkEventStreamUtils.extractToolCalls(event);

// Extract token usage metrics from an Event
AdkTokenUsage? usage = AdkEventStreamUtils.extractTokenUsage(event);

// Check if an event represents model consultation and extract metadata
if (AdkEventStreamUtils.isModelConsultEvent(event)) {
  final info = AdkEventStreamUtils.extractModelConsultInfo(event);
  print('Consulted ${info.advisorModel} because: ${info.escalationReason}');
}
```

### `AdkColorUtils`

```dart
// Resolve confidence colors according to Material 3 theme:
// >= 0.8: Green, >= 0.5: Orange, < 0.5: Error red
Color color = AdkColorUtils.confidenceColor(context, 0.92);

// Resolve workflow node status colors:
Color nodeColor = AdkColorUtils.nodeStatusColor(context, AdkGraphNodeStatus.running);
```

---

## 7. Copy-Paste Recipes

### Recipe 1: Handling Long-Running Tool Interrupts in a Chat Screen

```dart
class AgentChatScreen extends StatelessWidget {
  const AgentChatScreen({super.key, required this.events, required this.runner});

  final List<Event> events;
  final Runner runner;

  @override
  Widget build(BuildContext context) {
    final openInterrupts = AdkEventStreamUtils.extractOpenInterrupts(events);

    return Scaffold(
      appBar: AppBar(title: const Text('Agent Assistant')),
      body: Column(
        children: [
          // If any tool is paused waiting for user input, display the InterruptCard
          if (openInterrupts.isNotEmpty) ...[
            for (final entry in openInterrupts.entries)
              AdkInterruptCard(
                toolName: entry.value.toolName,
                interruptId: entry.key,
                reason: entry.value.prompt ?? 'Operation paused waiting for confirmation.',
                arguments: entry.value.arguments,
                requiresInput: entry.value.requiresInput,
                onResume: (input) {
                  runner.resume(
                    resumeInputs: {entry.key: input ?? true},
                  );
                },
                onCancel: () => runner.close(),
              ),
          ],
          const Expanded(
            child: Center(child: Text('Chat messages stream here...')),
          ),
        ],
      ),
    );
  }
}
```

### Recipe 2: Live Speech Assistant Screen with `AdkCascadeLiveBar`

```dart
class LiveVoiceScreen extends StatefulWidget {
  const LiveVoiceScreen({super.key});

  @override
  State<LiveVoiceScreen> createState() => _LiveVoiceScreenState();
}

class _LiveVoiceScreenState extends State<LiveVoiceScreen> {
  bool _isListening = true;
  bool _isSpeaking = false;
  bool _isBargeIn = false;
  String _transcript = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Assistant')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _transcript.isEmpty ? 'Tap microphone and start speaking' : _transcript,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: AdkCascadeLiveBar(
          isListening: _isListening,
          isSpeaking: _isSpeaking,
          isBargeIn: _isBargeIn,
          partialTranscript: _transcript,
          onMicToggle: () => setState(() => _isListening = !_isListening),
          onDisconnect: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
```
