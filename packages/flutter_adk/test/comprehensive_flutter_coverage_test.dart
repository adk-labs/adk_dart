import 'dart:async';
import 'dart:typed_data';
import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_adk/flutter_adk_platform_interface.dart';

class _MockAgent extends adk.BaseAgent {
  _MockAgent({
    super.name = 'mock_agent',
    super.description = 'Mock agent for testing',
  });

  Stream<adk.Event> Function(adk.InvocationContext context)? onRun;

  @override
  Stream<adk.Event> runAsyncImpl(adk.InvocationContext context) async* {
    if (onRun != null) {
      yield* onRun!(context);
    } else {
      yield adk.Event(
        id: 'mock_evt_1',
        invocationId: 'inv_1',
        author: name,
        content: adk.Content.modelText('Mock response'),
      );
    }
  }
}

class _MockRunner extends adk.Runner {
  _MockRunner({
    required super.agent,
    this.onRun,
  }) : super(
         appName: 'MockRunner',
         artifactService: adk.InMemoryArtifactService(),
         sessionService: adk.InMemorySessionService(),
         autoCreateSession: true,
       );

  final Stream<adk.Event> Function()? onRun;

  @override
  Stream<adk.Event> runAsync({
    required String userId,
    required String sessionId,
    adk.Content? newMessage,
    String? invocationId,
    Map<String, Object?>? stateDelta,
    adk.RunConfig? runConfig,
    adk.AdkAbortSignal? abortSignal,
  }) {
    if (onRun != null) {
      return onRun!();
    }
    return super.runAsync(
      userId: userId,
      sessionId: sessionId,
      newMessage: newMessage,
      invocationId: invocationId,
      stateDelta: stateDelta,
      runConfig: runConfig,
      abortSignal: abortSignal,
    );
  }
}

class _TestPlatform extends FlutterAdkPlatform {
  @override
  // ignore: unnecessary_overrides
  Future<String?> getPlatformVersion() => super.getPlatformVersion();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdkFloatingChatButton tests', () {
    testWidgets('renders button and opens bottom sheet on tap', (WidgetTester tester) async {
      final agent = _MockAgent();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: AdkFloatingChatButton(
              agent: agent,
              title: 'Test Assistant',
              tooltip: 'Ask AI',
            ),
          ),
        ),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.byType(AdkChatView), findsOneWidget);
      expect(find.text('Test Assistant'), findsOneWidget);

      // Close bottom sheet
      Navigator.of(tester.element(find.byType(AdkChatView))).pop();
      await tester.pumpAndSettle();
    });

    testWidgets('showChatBottomSheet static method works directly', (WidgetTester tester) async {
      final agent = _MockAgent();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AdkFloatingChatButton.showChatBottomSheet(
                context,
                agent: agent,
                title: 'Static Assistant',
                heightFactor: 0.9,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Static Assistant'), findsOneWidget);
    });
  });

  group('AdkInlineAssistantBar tests', () {
    testWidgets('preset actions and execution flow with preview card', (WidgetTester tester) async {
      final controller = TextEditingController(text: 'helo wrld');
      String? appliedResult;

      final agent = _MockAgent();
      agent.onRun = (ctx) async* {
        yield adk.Event(
          id: 'inline_evt_1',
          invocationId: 'inv_1',
          author: agent.name,
          content: adk.Content.modelText('Hello world!'),
        );
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AdkInlineAssistantBar(
                  agent: agent,
                  targetController: controller,
                  onResultApplied: (res) => appliedResult = res,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Fix Grammar'), findsOneWidget);
      expect(find.text('Make Formal'), findsOneWidget);
      expect(find.text('Summarize'), findsOneWidget);
      expect(find.text('Translate to English'), findsOneWidget);

      // Tap Fix Grammar
      await tester.tap(find.text('Fix Grammar'));
      await tester.pumpAndSettle();

      // Preview card is rendered
      expect(find.text('Hello world!'), findsOneWidget);
      expect(find.text('AI Suggestion (Fix Grammar)'), findsOneWidget);

      // Tap Copy
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      // Tap Apply
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(appliedResult, 'Hello world!');
      expect(controller.text, 'Hello world!');
      expect(find.text('AI Suggestion (Fix Grammar)'), findsNothing);
    });

    testWidgets('uses currentText and custom actionBuilder and dismisses preview', (WidgetTester tester) async {
      final agent = _MockAgent();
      agent.onRun = (ctx) async* {
        yield adk.Event(
          id: 'inline_evt_2',
          invocationId: 'inv_1',
          author: agent.name,
          content: adk.Content.modelText('Formal text'),
        );
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkInlineAssistantBar(
              agent: agent,
              currentText: 'Draft text',
              actionBuilder: (context, action, isRunning, onTrigger) {
                return ElevatedButton(
                  key: Key(action.label),
                  onPressed: onTrigger,
                  child: Text('Custom: ${action.label}'),
                );
              },
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('Fix Grammar')), findsOneWidget);
      await tester.tap(find.byKey(const Key('Fix Grammar')));
      await tester.pumpAndSettle();

      expect(find.text('Formal text'), findsOneWidget);

      // Dismiss preview
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Formal text'), findsNothing);
    });

    testWidgets('handles empty text and execution error gracefully', (WidgetTester tester) async {
      final agent = _MockAgent();
      final controller = TextEditingController(text: '');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkInlineAssistantBar(
              agent: agent,
              targetController: controller,
              runnerFactory: (a) => _MockRunner(
                agent: a,
                onRun: () => Stream<adk.Event>.error('Mock LLM error'),
              ),
            ),
          ),
        ),
      );

      // Empty text: tap should do nothing
      await tester.tap(find.text('Summarize'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Now set non-empty text and trigger error
      controller.text = 'Some input';
      await tester.tap(find.text('Summarize'));
      await tester.pumpAndSettle();

      expect(
        find.text('Error: Mock LLM error'),
        findsOneWidget,
      );
    });
  });

  group('AdkWorkflowController tests', () {
    test('execute, event handling, pauses, resume, cancel, reset', () async {
      final agent = _MockAgent();
      final controller = AdkWorkflowController(
        workflowAgent: agent,
        initialSteps: [
          const AdkWorkflowStep(id: 'step_1', label: 'Step 1'),
          const AdkWorkflowStep(id: 'step_2', label: 'Step 2'),
        ],
      );

      expect(controller.progress, 0.0);
      expect(controller.isCompleted, false);

      controller.setStepStatus('step_1', AdkStepStatus.running);
      expect(controller.steps.first.status, AdkStepStatus.running);

      controller.setStepStatus('step_1', AdkStepStatus.completed, output: 'Done 1');
      expect(controller.steps.first.status, AdkStepStatus.completed);
      expect(controller.progress, 0.5);

      controller.setStepStatus('step_2', AdkStepStatus.failed, errorMessage: 'Failed 2');
      expect(controller.steps[1].status, AdkStepStatus.failed);

      // Approve and resume
      await controller.approveAndResume(stepId: 'step_2', input: {'resolved': true});
      expect(controller.isCompleted, true);
      expect(controller.progress, 1.0);

      // Reset
      controller.reset();
      expect(controller.steps.first.status, AdkStepStatus.pending);
      expect(controller.isCompleted, false);
      expect(controller.progress, 0.0);

      // Progress with empty steps
      final emptyController = AdkWorkflowController(workflowAgent: agent);
      expect(emptyController.progress, 0.0);
      expect(emptyController.isCompleted, false);

      // Execute stream with HITL pause and completion
      agent.onRun = (ctx) async* {
        yield adk.Event(
          id: 'wf_evt_1',
          invocationId: 'inv_1',
          author: 'step_1',
          content: adk.Content.modelText('Step 1 output'),
        );
        yield adk.Event(
          id: 'wf_evt_2',
          invocationId: 'inv_1',
          author: 'pipeline',
          longRunningToolIds: {'tool_pause_42'},
        );
      };

      await controller.execute(inputPrompt: 'Start');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.isPaused, true);
      expect(controller.pausedStepId, 'tool_pause_42');

      // Cancel
      controller.cancel();
      expect(controller.isRunning, false);
      expect(controller.isPaused, false);

      controller.dispose();
      emptyController.dispose();
    });

    test('execute handles error stream', () async {
      final agent = _MockAgent();
      agent.onRun = (ctx) => Stream.error('Workflow engine crash');

      final controller = AdkWorkflowController(workflowAgent: agent);
      await controller.execute();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.currentError, contains('Workflow engine crash'));
      expect(controller.isRunning, false);
      controller.dispose();
    });
  });

  group('AdkChatMessage and Model tests', () {
    test('AdkCodeExecution properties, copyWith, equality and hash', () {
      const exec1 = AdkCodeExecution(
        language: 'PYTHON',
        code: 'x = 1',
        output: '1',
        outcome: 'OUTCOME_OK',
      );
      expect(exec1.isSuccess, true);

      const execFail = AdkCodeExecution(outcome: 'FAILED');
      expect(execFail.isSuccess, false);

      const execSuccess = AdkCodeExecution(outcome: 'SUCCESS');
      expect(execSuccess.isSuccess, true);

      final copy = exec1.copyWith(output: '2');
      expect(copy.output, '2');
      expect(copy.code, 'x = 1');
      expect(copy == exec1, false);

      final identicalCopy = exec1.copyWith();
      expect(identicalCopy, equals(exec1));
      expect(identicalCopy.hashCode, equals(exec1.hashCode));
    });

    test('AdkGroundingSource and AdkGroundingInfo equality and methods', () {
      const src1 = AdkGroundingSource(title: 'Google', uri: 'https://google.com');
      const src2 = AdkGroundingSource(title: 'Google', uri: 'https://google.com');
      const src3 = AdkGroundingSource(title: 'Other', uri: 'https://other.com');

      expect(src1, equals(src2));
      expect(src1.hashCode, equals(src2.hashCode));
      expect(src1 == src3, false);

      const info1 = AdkGroundingInfo(
        searchQueries: ['adk'],
        sources: [src1],
      );
      expect(info1.isEmpty, false);
      expect(info1.isNotEmpty, true);

      const emptyInfo = AdkGroundingInfo();
      expect(emptyInfo.isEmpty, true);

      const info2 = AdkGroundingInfo(
        searchQueries: ['adk'],
        sources: [src2],
      );
      expect(info1, equals(info2));
      expect(info1.hashCode, equals(info2.hashCode));
    });

    test('AdkChatMessage roles, getters, copyWith and equality', () {
      final userMsg = AdkChatMessage.user(id: 'u1', text: 'Hello');
      expect(userMsg.isUser, true);
      expect(userMsg.isModel, false);
      expect(userMsg.isTool, false);
      expect(userMsg.isSystem, false);
      expect(userMsg.isStreaming, false);
      expect(userMsg.isError, false);

      final modelMsg = AdkChatMessage.model(
        id: 'm1',
        text: 'Hi',
        isPartial: true,
        thought: 'Thinking...',
      );
      expect(modelMsg.isModel, true);
      expect(modelMsg.isStreaming, true);

      final toolMsg = AdkChatMessage.tool(
        id: 't1',
        toolName: 'calculator',
        toolArgs: {'a': 1},
        toolResult: 2,
      );
      expect(toolMsg.isTool, true);
      expect(toolMsg.toolArguments, {'a': 1});

      final sysMsg = AdkChatMessage.system(
        id: 's1',
        text: 'System alert',
        errorMessage: 'Fatal error',
      );
      expect(sysMsg.isSystem, true);
      expect(sysMsg.isError, true);

      final updated = userMsg.copyWith(
        text: 'Updated',
        isStreaming: true,
        toolArguments: {'x': 10},
      );
      expect(updated.text, 'Updated');
      expect(updated.isPartial, true);
      expect(updated.toolArgs, {'x': 10});

      final userCopy = userMsg.copyWith();
      expect(userCopy, equals(userMsg));
      expect(userCopy.hashCode, equals(userMsg.hashCode));
    });
  });

  group('AdkMessageBubble tests', () {
    testWidgets('renders user and model bubble with attachments and actions', (WidgetTester tester) async {
      bool tapped = false;
      bool longPressed = false;

      final attachment = AdkAttachment(
        name: 'test.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(<int>[
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
          0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
          0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
          0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
          0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
          0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
        ]),
      );
      final pdfAttachment = const AdkAttachment(
        name: 'document.pdf',
        mimeType: 'application/pdf',
      );

      final msg = AdkChatMessage.user(
        id: 'u1',
        text: 'User prompt with files',
        attachments: [attachment, pdfAttachment],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkMessageBubble(
              message: msg,
              showAvatar: true,
              showTimestamp: true,
              onTap: () => tapped = true,
              onLongPress: () => longPressed = true,
            ),
          ),
        ),
      );

      expect(find.text('User prompt with files'), findsOneWidget);
      expect(find.text('document.pdf'), findsOneWidget);

      final bubbleFinder = find.byType(InkWell);
      await tester.tap(bubbleFinder);
      await tester.pumpAndSettle();
      expect(tapped, true);

      await tester.longPressAt(tester.getTopLeft(bubbleFinder) + const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(longPressed, true);
    });

    testWidgets('renders model message with thought, code execution, grounding and custom builder', (WidgetTester tester) async {
      AdkGroundingSource? clickedSource;
      final msg = AdkChatMessage.model(
        id: 'm1',
        text: 'Model answer',
        thought: 'Internal reasoning',
        codeExecution: const AdkCodeExecution(
          language: 'PYTHON',
          code: 'print("hello")',
          output: 'hello\n',
        ),
        grounding: const AdkGroundingInfo(
          sources: [
            AdkGroundingSource(title: 'Citation 1', uri: 'https://example.com'),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkMessageBubble(
              message: msg,
              onGroundingSourceTap: (s) => clickedSource = s,
              timestampFormatter: (dt) => '12:00 PM',
              showTimestamp: true,
            ),
          ),
        ),
      );

      expect(find.text('Model answer'), findsOneWidget);
      expect(find.byType(AdkReasoningExpander), findsOneWidget);
      await tester.tap(find.byType(AdkReasoningExpander));
      await tester.pumpAndSettle();
      expect(find.text('Internal reasoning'), findsOneWidget);
      expect(find.text('print("hello")'), findsOneWidget);
      expect(find.text('Citation 1'), findsOneWidget);
      expect(find.text('12:00 PM'), findsOneWidget);

      await tester.tap(find.text('Citation 1'));
      expect(clickedSource?.title, 'Citation 1');
    });

    testWidgets('renders tool message with useToolCallCard true and false', (WidgetTester tester) async {
      final toolMsg = AdkChatMessage.tool(
        id: 't1',
        toolName: 'search_db',
        toolArgs: {'query': 'dart'},
        toolResult: 'result data',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AdkMessageBubble(message: toolMsg, useToolCallCard: true),
                AdkMessageBubble(message: toolMsg, useToolCallCard: false),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Tool: search_db'), findsOneWidget);
      expect(find.text('Tool Execution: search_db'), findsOneWidget);
    });

    testWidgets('renders system message with and without error', (WidgetTester tester) async {
      final normalSys = AdkChatMessage.system(id: 's1', text: 'Chat started');
      final errorSys = AdkChatMessage.system(
        id: 's2',
        text: 'Failure',
        errorMessage: 'Network disconnected',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AdkMessageBubble(message: normalSys),
                AdkMessageBubble(message: errorSys),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Chat started'), findsOneWidget);
      expect(find.text('Network disconnected'), findsOneWidget);
    });

    testWidgets('supports customContentBuilder and custom avatarBuilder', (WidgetTester tester) async {
      final msg = AdkChatMessage.user(id: 'u1', text: 'Custom bubble');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkMessageBubble(
              message: msg,
              showAvatar: true,
              avatarBuilder: (context, m) => const Icon(Icons.star, key: Key('custom_avatar')),
              customContentBuilder: (context, m) => const Text('Overridden content'),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('custom_avatar')), findsOneWidget);
      expect(find.text('Overridden content'), findsOneWidget);
    });
  });

  group('AdkWorkflowProgressIndicator tests', () {
    testWidgets('renders empty steps as SizedBox.shrink', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdkWorkflowProgressIndicator(steps: []),
          ),
        ),
      );
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('renders vertical and horizontal with all statuses', (WidgetTester tester) async {
      final steps = [
        const AdkWorkflowStep(id: 's1', label: 'Step 1', description: 'Desc 1', status: AdkStepStatus.completed),
        const AdkWorkflowStep(id: 's2', label: 'Step 2', description: 'Desc 2', status: AdkStepStatus.running),
        const AdkWorkflowStep(id: 's3', label: 'Step 3', description: '', status: AdkStepStatus.failed),
        const AdkWorkflowStep(id: 's4', label: 'Step 4', description: '', status: AdkStepStatus.skipped),
        const AdkWorkflowStep(id: 's5', label: 'Step 5', description: '', status: AdkStepStatus.pending),
      ];

      // Vertical
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdkWorkflowProgressIndicator(steps: steps, isVertical: true),
            ),
          ),
        ),
      );

      expect(find.text('Step 1'), findsOneWidget);
      expect(find.text('Desc 1'), findsOneWidget);
      expect(find.text('Step 2'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Horizontal
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkWorkflowProgressIndicator(steps: steps, isVertical: false),
          ),
        ),
      );

      expect(find.text('Step 1'), findsOneWidget);
      expect(find.text('Step 5'), findsOneWidget);
    });
  });

  group('AdkEventStreamBuilder tests', () {
    testWidgets('handles waiting, error, empty, and data states with custom builders', (WidgetTester tester) async {
      // 1. Data state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkEventStreamBuilder(
              key: const Key('data_stream'),
              stream: Stream.value(adk.Event(id: 'e1', invocationId: 'inv_1', author: 'agent')),
              builder: (context, events) => Text('Received: ${events.length}'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Received: 1'), findsOneWidget);

      // 2. Error state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkEventStreamBuilder(
              key: const Key('error_stream'),
              stream: Stream<adk.Event>.error('Stream broke'),
              errorBuilder: (context, err) => Text('Custom Error: $err'),
              builder: (context, events) => const Text('Data'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Custom Error: Stream broke'), findsOneWidget);

      // 3. Empty state
      final emptyCtrl = StreamController<adk.Event>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkEventStreamBuilder(
              key: const Key('empty_stream'),
              stream: emptyCtrl.stream,
              emptyBuilder: (context) => const Text('Custom Empty'),
              builder: (context, events) => const Text('Data'),
            ),
          ),
        ),
      );
      await emptyCtrl.close();
      await tester.pump();
      expect(find.text('Custom Empty'), findsOneWidget);
    });

    testWidgets('uses default loading and error builders', (WidgetTester tester) async {
      final controller = StreamController<adk.Event>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkEventStreamBuilder(
              stream: controller.stream,
              builder: (context, events) => const Text('Data'),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      controller.addError('Default err');
      await tester.pump();
      expect(find.text('Error: Default err'), findsOneWidget);

      await controller.close();
    });
  });

  group('AdkVoiceController tests', () {
    test('startListening, stopListening, startSpeaking, interrupt, amplitude, transcripts', () async {
      bool listenStarted = false;
      bool listenStopped = false;
      String? spokenText;
      bool interrupted = false;

      final controller = AdkVoiceController(
        onListenStart: () async => listenStarted = true,
        onListenStop: () async {
          listenStopped = true;
          return 'Transcribed speech';
        },
        onSpeak: (txt) async => spokenText = txt,
        onSpeechInterrupt: () async => interrupted = true,
      );

      expect(controller.state.status, AdkVoiceStatus.idle);
      expect(controller.isListening, false);
      expect(controller.isSpeaking, false);
      expect(controller.isMuted, false);

      // Start listening
      await controller.startListening();
      expect(listenStarted, true);
      expect(controller.isListening, true);

      // Amplitude update
      controller.updateAmplitude(0.75);
      expect(controller.decibels, 0.75);

      // Toggle mute
      controller.toggleMute();
      expect(controller.isMuted, true);
      controller.toggleMute();
      expect(controller.isMuted, false);

      // Stop listening
      await controller.stopListening();
      expect(listenStopped, true);
      expect(controller.userTranscript, 'Transcribed speech');

      // Start speaking
      await controller.startSpeaking(text: 'Hello from AI');
      expect(controller.isSpeaking, true);
      expect(spokenText, 'Hello from AI');
      expect(controller.agentTranscript, 'Hello from AI');

      // Stop speaking
      controller.stopSpeaking();
      expect(controller.isSpeaking, false);
      expect(controller.state.status, AdkVoiceStatus.idle);

      // Interrupt
      controller.interrupt();
      expect(interrupted, true);

      // Status override
      controller.setVoiceStatus(AdkVoiceStatus.error, errorMessage: 'Mic failed');
      expect(controller.state.status, AdkVoiceStatus.error);
      expect(controller.state.errorMessage, 'Mic failed');

      controller.dispose();
    });

    test('handles errors in delegates', () async {
      final controller = AdkVoiceController(
        onListenStart: () async => throw 'STT init fail',
        onListenStop: () async => throw 'STT proc fail',
        onSpeak: (txt) async => throw 'TTS fail',
      );

      await controller.startListening();
      expect(controller.state.status, AdkVoiceStatus.error);
      expect(controller.state.errorMessage, contains('STT start error'));

      await controller.stopListening();
      expect(controller.state.status, AdkVoiceStatus.error);
      expect(controller.state.errorMessage, contains('STT stop error'));

      await controller.startSpeaking(text: 'Speak');
      expect(controller.state.status, AdkVoiceStatus.error);
      expect(controller.state.errorMessage, contains('TTS playback error'));

      controller.dispose();
    });
  });

  group('AdkChatController advanced coverage', () {
    test('handles compaction, grounding, code execution, and errors in event stream', () async {
      final agent = _MockAgent();
      final controller = AdkChatController(agent: agent);

      agent.onRun = (ctx) async* {
        // Compaction event
        yield adk.Event(
          id: 'comp_1',
          invocationId: 'inv_1',
          author: 'system',
          actions: adk.EventActions(
            compaction: adk.EventCompaction(
              compactedContent: adk.Content.modelText('Compacted summary'),
              startTimestamp: 0.0,
              endTimestamp: 10.0,
            ),
          ),
        );

        // Grounding & Code Execution
        yield adk.Event(
          id: 'model_1',
          invocationId: 'inv_1',
          author: agent.name,
          groundingMetadata: {
            'webSearchQueries': ['dart flutter adk'],
            'groundingChunks': [
              {
                'web': {'title': 'Dart Docs', 'uri': 'https://dart.dev'},
              },
            ],
          },
          content: adk.Content(
            role: 'model',
            parts: [
              adk.Part(text: 'Thinking about code...', thought: true),
              adk.Part(text: 'Here is the answer: 42'),
              adk.Part(executableCode: {'language': 'PYTHON', 'code': 'print(42)'}),
              adk.Part(codeExecutionResult: {'outcome': 'OUTCOME_OK', 'output': '42\n'}),
            ],
          ),
        );

        // Tool call
        yield adk.Event(
          id: 'tool_call_1',
          invocationId: 'inv_1',
          author: 'agent',
          content: adk.Content(
            parts: [
              adk.Part(functionCall: adk.FunctionCall(name: 'calc', args: {'x': 10})),
            ],
          ),
        );

        // Tool response
        yield adk.Event(
          id: 'tool_resp_1',
          invocationId: 'inv_1',
          author: 'tool',
          content: adk.Content(
            parts: [
              adk.Part(functionResponse: adk.FunctionResponse(name: 'calc', response: {'result': 20})),
            ],
          ),
        );

        // Content null with agent state
        yield adk.Event(
          id: 'state_1',
          invocationId: 'inv_1',
          author: 'agent',
          actions: adk.EventActions(
            agentState: {'step': 'finished'},
          ),
        );
      };

      await controller.sendMessage('Test prompt');

      expect(controller.messages.any((m) => m.isCompaction), true);
      expect(controller.messages.any((m) => m.codeExecution != null), true);
      expect(controller.messages.any((m) => m.grounding != null), true);
      expect(controller.messages.any((m) => m.isTool), true);

      // Export JSON
      final jsonPretty = controller.exportTranscriptJson(pretty: true);
      final jsonCompact = controller.exportTranscriptJson(pretty: false);
      expect(jsonPretty, contains('dart flutter adk'));
      expect(jsonCompact, contains('calc'));

      // Clear & stop
      controller.stopGeneration();
      controller.clearMessages();
      expect(controller.messages, isEmpty);

      controller.dispose();
    });

    test('loadSession with history and session compaction', () async {
      final storage = AdkMemoryStorage();
      final sessionService = AdkStorageSessionService(storage: storage);

      final session = await sessionService.createSession(
        appName: 'test_app',
        userId: 'test_user',
        sessionId: 'session_1',
      );

      final compactionEvent = adk.Event(
        id: 'hist_comp',
        invocationId: 'inv_1',
        author: 'system',
        actions: adk.EventActions(
          compaction: adk.EventCompaction(
            compactedContent: adk.Content.modelText('Previous conversation summary'),
            startTimestamp: 0.0,
            endTimestamp: 10.0,
          ),
        ),
      );

      final modelEvent = adk.Event(
        id: 'hist_model',
        invocationId: 'inv_1',
        author: 'assistant',
        groundingMetadata: {
          'web_search_queries': ['history query'],
          'grounding_chunks': [
            {
              'retrievedContext': {'title': 'Doc', 'uri': 'https://doc.org'},
            },
          ],
        },
        content: adk.Content(
          role: 'model',
          parts: [
            adk.Part(text: 'Historical response'),
            adk.Part(executableCode: {'language': 'PYTHON', 'code': 'a = 1'}),
            adk.Part(codeExecutionResult: {'outcome': 'OUTCOME_OK', 'output': '1'}),
            adk.Part(functionCall: adk.FunctionCall(name: 'lookup', args: {'k': 'v'})),
            adk.Part(functionResponse: adk.FunctionResponse(name: 'lookup', response: {'result': 'val'})),
          ],
        ),
      );

      await sessionService.appendEvent(session: session, event: compactionEvent);
      await sessionService.appendEvent(session: session, event: modelEvent);

      final controller = AdkChatController(
        agent: _MockAgent(),
        appName: 'test_app',
        userId: 'test_user',
        sessionId: 'session_1',
        sessionService: sessionService,
      );

      await controller.loadSession();

      expect(controller.messages.any((m) => m.isCompaction), true);
      expect(controller.messages.any((m) => m.text == 'Historical response'), true);
      expect(controller.messages.any((m) => m.toolName == 'lookup'), true);

      controller.dispose();
    });
  });

  group('AdkAgentLoggerController tests', () {
    test('rollover buffer, recordEvent, filters, exportJson and clear', () {
      final logger = AdkAgentLoggerController(maxLogEntries: 3);

      logger.recordEvent(
        adk.Event(
          id: 'e1',
          invocationId: 'inv_1',
          author: 'user',
          content: adk.Content.userText('Hello agent'),
        ),
      );
      expect(logger.logs.length, 1);
      expect(logger.logs.first.category, AdkLogCategory.userInput);

      logger.recordEvent(
        adk.Event(
          id: 'e2',
          invocationId: 'inv_1',
          author: 'agent',
          content: adk.Content(
            parts: [adk.Part(functionCall: adk.FunctionCall(name: 'fetch_data', args: {'id': 101}))],
          ),
        ),
      );
      expect(logger.logs.length, 2);
      expect(logger.logs.last.category, AdkLogCategory.toolCall);

      logger.recordEvent(
        adk.Event(
          id: 'e3',
          invocationId: 'inv_1',
          author: 'tool',
          content: adk.Content(
            parts: [adk.Part(functionResponse: adk.FunctionResponse(name: 'fetch_data', response: {'status': 'ok'}))],
          ),
        ),
      );
      expect(logger.logs.length, 3);

      // Rollover
      logger.recordEvent(
        adk.Event(
          id: 'e4',
          invocationId: 'inv_1',
          author: 'agent',
          content: adk.Content.modelText('Final reply'),
        ),
      );
      expect(logger.logs.length, 3);
      expect(logger.logs.first.id, contains('e2'));

      // Category and search query
      logger.setCategory(AdkLogCategory.toolCall);
      expect(logger.selectedCategory, AdkLogCategory.toolCall);
      expect(logger.filteredLogs.length, 2);

      logger.setSearchQuery('101');
      expect(logger.filteredLogs.length, 1);

      // AutoScroll toggle
      logger.toggleAutoScroll();
      expect(logger.autoScroll, false);

      // Export
      final jsonPretty = logger.exportJson(pretty: true);
      final jsonCompact = logger.exportJson(pretty: false);
      expect(jsonPretty, contains('fetch_data'));
      expect(jsonCompact, contains('fetch_data'));

      // Clear
      logger.clearLogs();
      expect(logger.logs, isEmpty);
    });
  });

  group('AdkDevStudioView tests', () {
    testWidgets('renders all 4 tabs, logger updates, agent graph, and state inspector', (WidgetTester tester) async {
      final subAgent = _MockAgent(name: 'child_agent', description: 'Sub worker');
      final rootAgent = adk.LlmAgent(
        name: 'orchestrator',
        model: 'gemini-3.7-flash',
        description: 'Lead orchestrator',
        subAgents: [subAgent],
      );

      final controller = AdkChatController(agent: rootAgent);

      await tester.pumpWidget(
        MaterialApp(
          home: AdkDevStudioView(
            agent: rootAgent,
            controller: controller,
            initialState: const {'counter': 100, 'flag': true},
          ),
        ),
      );

      expect(find.text('Playground'), findsOneWidget);
      expect(find.text('Live Logger'), findsOneWidget);
      expect(find.text('Agent Graph'), findsOneWidget);
      expect(find.text('State & Session'), findsOneWidget);

      // Switch to Live Logger tab
      await tester.tap(find.text('Live Logger'));
      await tester.pumpAndSettle();
      expect(find.byType(AdkAgentLoggerView), findsOneWidget);

      // Switch to Agent Graph tab
      await tester.tap(find.text('Agent Graph'));
      await tester.pumpAndSettle();
      expect(find.text('orchestrator'), findsOneWidget);
      expect(find.text('Lead orchestrator'), findsOneWidget);
      expect(find.text('child_agent'), findsOneWidget);

      // Switch to State & Session tab
      await tester.tap(find.text('State & Session'));
      await tester.pumpAndSettle();
      expect(find.text('counter'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
    });

    testWidgets('renders fallback when agent has no subagents and state is empty', (WidgetTester tester) async {
      final minimalAgent = _MockAgent(name: 'plain_agent', description: '');

      await tester.pumpWidget(
        MaterialApp(
          home: AdkDevStudioView(
            agent: minimalAgent,
            initialState: const {},
          ),
        ),
      );

      // Switch to State & Session tab
      await tester.tap(find.text('State & Session'));
      await tester.pumpAndSettle();
      expect(find.text('No state variables stored in this session.'), findsOneWidget);
    });
  });

  group('AdkUIUtils, Formatters, and ColorUtils tests', () {
    test('AdkFormatters tokens, durations, bytes, and json', () {
      expect(AdkFormatters.formatTokens(500), '500 tokens');
      expect(AdkFormatters.formatTokens(500, compact: true), '500');
      expect(AdkFormatters.formatTokens(5400), '5.4k tokens');
      expect(AdkFormatters.formatTokens(5400, compact: true), '5.4k');
      expect(AdkFormatters.formatTokens(15000, compact: true), '15k');
      expect(AdkFormatters.formatTokens(2500000), '2.5M tokens');
      expect(AdkFormatters.formatTokens(2500000, compact: true), '2.5M');

      expect(AdkFormatters.formatDuration(const Duration(milliseconds: 300)), '300ms');
      expect(AdkFormatters.formatDuration(const Duration(milliseconds: 2500)), '2.50s');
      expect(AdkFormatters.formatDuration(const Duration(minutes: 3, seconds: 12)), '3m 12s');

      expect(AdkFormatters.formatBytes(512), '512 B');
      expect(AdkFormatters.formatBytes(1024 * 300), '300.0 KB');
      expect(AdkFormatters.formatBytes(1024 * 1024 * 5), '5.0 MB');

      expect(AdkFormatters.formatJson(null), '');
      expect(AdkFormatters.formatJson({'a': 1}), contains('"a": 1'));
    });

    test('AdkEventStreamUtils extractToolCalls, extractTokenUsage, isModelConsult', () {
      final eventWithCalls = adk.Event(
        id: 'e1',
        invocationId: 'inv_1',
        author: 'agent',
        timestamp: 1700000000,
        content: adk.Content(
          parts: [
            adk.Part(functionCall: adk.FunctionCall(id: 'call_1', name: 'search', args: {'q': 'flutter'})),
          ],
        ),
      );
      final calls = AdkEventStreamUtils.extractToolCalls(eventWithCalls);
      expect(calls.length, 1);
      expect(calls.first.toolName, 'search');
      expect(calls.first.callId, 'call_1');

      final emptyCalls = AdkEventStreamUtils.extractToolCalls(adk.Event(id: 'e2', invocationId: 'inv_1', author: 'a'));
      expect(emptyCalls, isEmpty);

      // Usage
      final eventWithUsage = adk.Event(
        id: 'e3',
        invocationId: 'inv_1',
        author: 'agent',
        usageMetadata: {
          'prompt_token_count': 100,
          'candidates_token_count': 50,
          'total_token_count': 150,
          'thought_tokens': 20,
        },
      );
      final usage = AdkEventStreamUtils.extractTokenUsage(eventWithUsage);
      expect(usage?.promptTokens, 100);
      expect(usage?.completionTokens, 50);
      expect(usage?.totalTokens, 150);
      expect(usage?.thoughtTokens, 20);

      // Model consult
      final consultEvent = adk.Event(
        id: 'e4',
        invocationId: 'inv_1',
        author: 'agent',
        customMetadata: {
          'advisor_model': 'gemini-1.5-pro',
          'escalation_reason': 'complex coding',
          'turn_count': 1,
          'turn_budget': 3,
        },
        content: adk.Content(
          parts: [adk.Part(functionCall: adk.FunctionCall(name: 'consult_model', args: {}))],
        ),
      );
      expect(AdkEventStreamUtils.isModelConsultEvent(consultEvent), true);
      final consultInfo = AdkEventStreamUtils.extractModelConsultInfo(consultEvent);
      expect(consultInfo.advisorModel, 'gemini-1.5-pro');
      expect(consultInfo.escalationReason, 'complex coding');
    });

    testWidgets('AdkColorUtils confidenceColor and nodeStatusColor', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              expect(AdkColorUtils.confidenceColor(context, 0.9), isNotNull);
              expect(AdkColorUtils.confidenceColor(context, 0.6), isNotNull);
              expect(AdkColorUtils.confidenceColor(context, 0.3), isNotNull);

              expect(AdkColorUtils.nodeStatusColor(context, AdkGraphNodeStatus.completed), isNotNull);
              expect(AdkColorUtils.nodeStatusColor(context, AdkGraphNodeStatus.running), isNotNull);
              expect(AdkColorUtils.nodeStatusColor(context, AdkGraphNodeStatus.failed), isNotNull);
              expect(AdkColorUtils.nodeStatusColor(context, AdkGraphNodeStatus.skipped), isNotNull);
              expect(AdkColorUtils.nodeStatusColor(context, AdkGraphNodeStatus.pending), isNotNull);

              return const SizedBox();
            },
          ),
        ),
      );
    });
  });

  group('AdkAgentPersonaSelector tests', () {
    testWidgets('renders horizontal list, cardBuilder, and header', (WidgetTester tester) async {
      final personas = [
        const AdkPersona(id: 'coder', name: 'Software Engineer', description: 'Writes clean code', icon: Icons.code),
        const AdkPersona(id: 'writer', name: 'Technical Writer', description: 'Drafts docs', icon: Icons.edit),
      ];

      AdkPersona? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentPersonaSelector(
              personas: personas,
              isGrid: false,
              selectedPersonaId: 'coder',
              header: const Text('Choose Persona'),
              onPersonaSelected: (p) => selected = p,
            ),
          ),
        ),
      );

      expect(find.text('Choose Persona'), findsOneWidget);
      expect(find.text('Software Engineer'), findsOneWidget);
      expect(find.text('Technical Writer'), findsOneWidget);

      await tester.tap(find.text('Technical Writer'));
      expect(selected?.id, 'writer');
    });

    testWidgets('supports custom cardBuilder in grid and list', (WidgetTester tester) async {
      final personas = [
        const AdkPersona(id: 'p1', name: 'Persona 1', description: 'Desc 1', icon: Icons.star),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkAgentPersonaSelector(
              personas: personas,
              isGrid: false,
              cardBuilder: (context, persona, isSelected, onSelect) {
                return ElevatedButton(
                  onPressed: onSelect,
                  child: Text('Custom: ${persona.name}'),
                );
              },
              onPersonaSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Custom: Persona 1'), findsOneWidget);
    });
  });

  group('AdkSmartFormController tests', () {
    test('fields, fieldMap, updateFieldValue, populateFromMap, submit, and reset', () async {
      Map<String, String>? submittedData;

      final controller = AdkSmartFormController(
        initialFields: const [
          AdkFormField(key: 'username', label: 'Username', isRequired: true),
          AdkFormField(key: 'age', label: 'Age', isRequired: false),
        ],
        onSubmitted: (data) => submittedData = data,
      );

      expect(controller.fields.length, 2);
      expect(controller.fieldMap.containsKey('username'), true);
      expect(controller.totalCount, 2);
      expect(controller.filledCount, 0);
      expect(controller.progress, 0.0);
      expect(controller.isReady, false);

      // Validate fails when required field is empty
      final missing = controller.validate();
      expect(missing, ['username']);
      expect(controller.errorMessage, contains('username'));

      // Update field value
      controller.updateFieldValue('username', 'alice');
      expect(controller.filledCount, 1);
      expect(controller.isReady, true);
      expect(controller.errorMessage, isNull);

      // Populate from map
      controller.populateFromMap({'age': '30'});
      expect(controller.filledCount, 2);
      expect(controller.progress, 1.0);

      // Submit
      final success = await controller.submit();
      expect(success, true);
      expect(submittedData, {'username': 'alice', 'age': '30'});
      expect(controller.isCompleted, true);

      // Reset
      controller.reset();
      expect(controller.filledCount, 0);
      expect(controller.isCompleted, false);

      // Submit when onSubmitted throws
      final throwingController = AdkSmartFormController(
        initialFields: const [AdkFormField(key: 'k', label: 'K', isRequired: false)],
        onSubmitted: (_) => throw Exception('Submission failed'),
      );
      final fail = await throwingController.submit();
      expect(fail, false);
      expect(throwingController.errorMessage, contains('Submission failed'));
    });
  });

  group('AdkSplitPaneView tests', () {
    testWidgets('renders narrow vs wide split panes with custom builders', (WidgetTester tester) async {
      final agent = _MockAgent();
      final controller = AdkChatController(agent: agent);

      // Narrow screen
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkSplitPaneView(
              agent: agent,
              controller: controller,
              breakpoint: 900,
            ),
          ),
        ),
      );

      expect(find.byType(AdkChatView), findsOneWidget);

      // Wide screen
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkSplitPaneView(
              agent: agent,
              controller: controller,
              breakpoint: 900,
              showLogger: true,
              showToolInspector: true,
            ),
          ),
        ),
      );

      expect(find.byType(VerticalDivider), findsOneWidget);
      expect(find.text('Logger'), findsOneWidget);
      expect(find.text('Tools'), findsOneWidget);
    });
  });

  group('AdkAttachment tests', () {
    test('toPart, equality and hashCode', () {
      final textAtt = const AdkAttachment(name: 'notes.txt', mimeType: 'text/plain');
      final part = textAtt.toPart();
      expect(part.text, 'Attachment: notes.txt');

      final uriAtt = const AdkAttachment(
        name: 'cloud.pdf',
        mimeType: 'application/pdf',
        uri: 'gs://bucket/file.pdf',
      );
      final uriPart = uriAtt.toPart();
      expect(uriPart.fileData?.fileUri, 'gs://bucket/file.pdf');

      const att1 = AdkAttachment(name: 'a.png', mimeType: 'image/png');
      const att2 = AdkAttachment(name: 'a.png', mimeType: 'image/png');
      expect(att1, equals(att2));
      expect(att1.hashCode, equals(att2.hashCode));
    });
  });

  group('AdkStorage and Platform tests', () {
    test('AdkMemoryStorage and AdkCustomStorage', () async {
      final mem = AdkMemoryStorage();
      mem.write('key1', 'val1');
      mem.write('pref_key2', 'val2');

      expect(mem.read('key1'), 'val1');
      expect(mem.getKeys().length, 2);
      expect(mem.getKeys(prefix: 'pref_').length, 1);

      mem.delete('key1');
      expect(mem.read('key1'), isNull);

      final custom = AdkCustomStorage(
        read: (k) => 'custom_$k',
        write: (k, v) {},
        delete: (k) {},
        getKeys: ({prefix = ''}) => ['k1', 'k2'],
      );
      expect(await custom.read('test'), 'custom_test');
      expect(await custom.getKeys(), ['k1', 'k2']);
      await custom.write('k', 'v');
      await custom.delete('k');
    });

    test('FlutterAdkPlatform default implementation throws UnimplementedError', () async {
      final platform = _TestPlatform();
      expect(() => platform.getPlatformVersion(), throwsUnimplementedError);
    });
  });

  group('AdkAgentMetadata and Metrics tests', () {
    test('copyWith on AdkAgentMetrics and AdkAgentMetadata', () {
      const metrics = AdkAgentMetrics(totalInvocations: 10, totalTokens: 1000);
      final updatedMetrics = metrics.copyWith(errorCount: 2);
      expect(updatedMetrics.errorCount, 2);
      expect(updatedMetrics.totalInvocations, 10);

      final meta = AdkAgentMetadata(
        id: 'agent_1',
        name: 'Agent 1',
        agent: _MockAgent(),
      );
      final updatedMeta = meta.copyWith(
        description: 'New desc',
        isEnabled: false,
        status: AdkAgentStatus.disabled,
      );
      expect(updatedMeta.description, 'New desc');
      expect(updatedMeta.isEnabled, false);
      expect(updatedMeta.status, AdkAgentStatus.disabled);
    });
  });

  group('AdkAgentManagerController tests', () {
    test('all methods, tags, activeAgent, registration, metrics, and filtering', () {
      final a1 = _MockAgent(name: 'agent_1');
      final a2 = _MockAgent(name: 'agent_2');

      final manager = AdkAgentManagerController(initialAgents: [a1, a2]);
      expect(manager.agents.length, 2);
      expect(manager.activeAgentId, 'agent_1');
      expect(manager.activeAgent?.id, 'agent_1');

      manager.setActiveAgent('agent_2');
      expect(manager.activeAgentId, 'agent_2');

      manager.toggleAgent('agent_1', false);
      expect(manager.enabledAgents.length, 1);

      manager.recordInvocation('agent_2', tokens: 150, latencyMs: 250.0, isError: false);
      expect(manager.getAgent('agent_2')?.metrics.totalTokens, 150);

      manager.updateInstruction('agent_2', 'You are helpful');
      expect(manager.getAgent('agent_2')?.instruction, 'You are helpful');

      manager.setSearchQuery('agent_2');
      expect(manager.filteredAgents.length, 1);

      manager.unregisterAgent('agent_2');
      expect(manager.activeAgentId, 'agent_1');

      manager.clearAll();
      expect(manager.agents, isEmpty);
      expect(manager.activeAgent, isNull);
    });
  });

  group('AdkSessionController tests', () {
    test('loadAllSessions, createNewSession, updateTitle, delete, and clear', () async {
      final storage = AdkMemoryStorage();
      final controller = AdkSessionController(
        storage: storage,
        appName: 'app',
        userId: 'user',
      );

      final s1 = await controller.createNewSession(title: 'Chat 1', sessionId: 's1');
      expect(s1.id, 's1');
      expect(controller.sessions.length, 1);
      expect(controller.activeSession?.id, 's1');

      await controller.updateSessionTitle('s1', 'Renamed Chat');
      expect(controller.activeSession?.title, 'Renamed Chat');

      final s2 = await controller.createNewSession(title: 'Chat 2', sessionId: 's2');
      expect(s2.id, 's2');
      expect(controller.sessions.length, 2);
      expect(controller.activeSessionId, 's2');

      controller.switchSession('s1');
      expect(controller.activeSessionId, 's1');

      controller.setSearchQuery('Renamed');
      expect(controller.filteredSessions.length, 1);

      await controller.deleteSession('s1');
      expect(controller.sessions.length, 1);
      expect(controller.activeSessionId, 's2');

      await controller.clearAllSessions();
      expect(controller.sessions, isEmpty);
      expect(controller.activeSessionId, isNull);
    });
  });

  group('AdkStorageSessionService tests', () {
    test('inMemory, custom, duplicate createSession, and recent events slicing', () async {
      final inMemory = AdkStorageSessionService.inMemory();
      final session = await inMemory.createSession(
        appName: 'app',
        userId: 'u',
        sessionId: 'test_s',
      );

      expect(() => inMemory.createSession(
        appName: 'app',
        userId: 'u',
        sessionId: 'test_s',
      ), throwsA(isA<adk.AlreadyExistsError>()));

      // Append 5 events
      for (int i = 0; i < 5; i++) {
        await inMemory.appendEvent(
          session: session,
          event: adk.Event(id: 'e_$i', invocationId: 'inv_1', author: 'user', content: adk.Content.userText('msg $i')),
        );
      }

      // Slicing recent events
      final sliced = await inMemory.getSession(
        appName: 'app',
        userId: 'u',
        sessionId: 'test_s',
        config: adk.GetSessionConfig(numRecentEvents: 2),
      );
      expect(sliced?.events.length, 2);
      expect(sliced?.events.first.id, 'e_3');

      // Custom constructor
      final customService = AdkStorageSessionService.custom(
        read: (k) => null,
        write: (k, v) {},
        delete: (k) {},
        getKeys: ({prefix = ''}) => [],
      );
      expect(await customService.getSession(appName: 'a', userId: 'u', sessionId: 's'), isNull);
    });
  });

  group('AdkArtifactItem and Viewer tests', () {
    test('AdkArtifactItem file type checks', () {
      const codeItem = AdkArtifactItem(name: 'main.dart');
      expect(codeItem.isCodeOrJson, true);
      expect(codeItem.isMarkdown, false);

      const mdItem = AdkArtifactItem(name: 'README.md');
      expect(mdItem.isCodeOrJson, false);
      expect(mdItem.isMarkdown, true);
    });

    testWidgets('AdkArtifactCard tap opens AdkArtifactViewer dialog and actions work', (WidgetTester tester) async {
      bool downloaded = false;
      bool saved = false;

      const artifact = AdkArtifactItem(
        name: 'report.json',
        content: '{"status": "ok"}',
        version: '1',
        sizeBytes: 2048,
        mimeType: 'application/json',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkArtifactCard(
              artifact: artifact,
              onDownload: () => downloaded = true,
            ),
          ),
        ),
      );

      expect(find.text('report.json'), findsOneWidget);
      expect(find.text('v1 • '), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.download_rounded));
      expect(downloaded, true);

      // Open dialog
      await tester.tap(find.byType(AdkArtifactCard));
      await tester.pumpAndSettle();

      expect(find.byType(AdkArtifactViewer), findsOneWidget);
      expect(find.text('{"status": "ok"}'), findsOneWidget);

      // Copy content
      await tester.tap(find.byTooltip('Copy to Clipboard'));
      await tester.pump();

      // Close dialog
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(AdkArtifactViewer), findsNothing);

      // Test AdkArtifactViewer directly with onSave
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdkArtifactViewer(
              artifact: artifact,
              onSave: () => saved = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Save Artifact'));
      expect(saved, true);
    });
  });
}
