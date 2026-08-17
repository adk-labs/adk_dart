import 'dart:async';
import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/foundation.dart';

import '../models/adk_workflow_step_model.dart';

/// A reactive controller for orchestrating and observing ADK 2.0 Workflows and multi-agent pipelines.
class AdkWorkflowController extends ChangeNotifier {
  /// Creates an [AdkWorkflowController].
  AdkWorkflowController({
    required this.workflowAgent,
    List<AdkWorkflowStep>? initialSteps,
    this.userId = 'workflow_user',
    String? sessionId,
  })  : _steps = initialSteps != null ? List<AdkWorkflowStep>.from(initialSteps) : <AdkWorkflowStep>[],
        sessionId = sessionId ?? 'workflow_session_${DateTime.now().millisecondsSinceEpoch}';

  /// The root workflow agent (e.g. [adk.SequentialAgent], [adk.ParallelAgent], [adk.LoopAgent]).
  final adk.BaseAgent workflowAgent;

  /// User identifier.
  final String userId;

  /// Session identifier.
  final String sessionId;

  final List<AdkWorkflowStep> _steps;
  bool _isRunning = false;
  bool _isPaused = false;
  String? _pausedStepId;
  String? _currentError;
  int? _currentStepIndex;
  StreamSubscription<adk.Event>? _subscription;

  /// List of workflow steps in execution order.
  List<AdkWorkflowStep> get steps => List<AdkWorkflowStep>.unmodifiable(_steps);

  /// Whether the workflow is actively executing.
  bool get isRunning => _isRunning;

  /// Whether the workflow is currently paused waiting for HITL approval.
  bool get isPaused => _isPaused;

  /// ID of the step where execution is paused.
  String? get pausedStepId => _pausedStepId;

  /// Error message if the workflow failed.
  String? get currentError => _currentError;

  /// Index of the step currently being executed.
  int? get currentStepIndex => _currentStepIndex;

  /// Total progress ratio (0.0 to 1.0).
  double get progress {
    if (_steps.isEmpty) return 0.0;
    final int completed = _steps.where((AdkWorkflowStep s) => s.status == .completed).length;
    return completed / _steps.length;
  }

  /// Whether all steps have completed successfully.
  bool get isCompleted => _steps.isNotEmpty && _steps.every((AdkWorkflowStep s) => s.status == .completed);

  /// Starts executing the workflow from the beginning or with an initial input.
  Future<void> execute({String? inputPrompt, Map<String, dynamic>? state}) async {
    if (_isRunning) return;

    _isRunning = true;
    _isPaused = false;
    _pausedStepId = null;
    _currentError = null;
    notifyListeners();

    final adk.Runner runner = adk.InMemoryRunner(agent: workflowAgent);
    final String prompt = inputPrompt ?? 'Start workflow execution';

    try {
      final Stream<adk.Event> eventStream = runner.runAsync(
        userId: userId,
        sessionId: sessionId,
        newMessage: adk.Content.userText(prompt),
      );

      _subscription = eventStream.listen(
        (adk.Event event) {
          _handleWorkflowEvent(event);
        },
        onError: (Object error) {
          _currentError = error.toString();
          _isRunning = false;
          notifyListeners();
        },
        onDone: () {
          _isRunning = false;
          _isPaused = false;
          notifyListeners();
        },
      );
    } catch (e) {
      _currentError = e.toString();
      _isRunning = false;
      notifyListeners();
    }
  }

  void _handleWorkflowEvent(adk.Event event) {
    // Check if event signals pause for human-in-the-loop
    if (event.longRunningToolIds != null && event.longRunningToolIds!.isNotEmpty) {
      _isPaused = true;
      _pausedStepId = event.longRunningToolIds!.first;
      notifyListeners();
      return;
    }

    // Match step with event author or tool
    final String author = event.author;
    final int stepIdx = _steps.indexWhere((AdkWorkflowStep s) => s.id == author || s.label.toLowerCase() == author.toLowerCase());

    if (stepIdx >= 0) {
      _currentStepIndex = stepIdx;
      final AdkWorkflowStep current = _steps[stepIdx];
      final content = event.content;
      final dynamic output = content?.parts.map((p) => p.text).whereType<String>().join('\n');

      _steps[stepIdx] = current.copyWith(
        status: .completed,
        endTime: DateTime.now(),
        output: output,
      );
      notifyListeners();
    }
  }

  /// Manually marks a step with a new status and optional output.
  void setStepStatus(String stepId, AdkStepStatus status, {dynamic output, String? errorMessage}) {
    final int idx = _steps.indexWhere((AdkWorkflowStep s) => s.id == stepId);
    if (idx >= 0) {
      _steps[idx] = _steps[idx].copyWith(
        status: status,
        output: output,
        errorMessage: errorMessage,
        endTime: (status == .completed || status == .failed) ? DateTime.now() : null,
      );
      notifyListeners();
    }
  }

  /// Approves a paused step and resumes execution.
  Future<void> approveAndResume({required String stepId, Map<String, dynamic>? input}) async {
    _isPaused = false;
    _pausedStepId = null;
    setStepStatus(stepId, .completed, output: input);
    notifyListeners();
  }

  /// Cancels any active workflow execution.
  void cancel() {
    _subscription?.cancel();
    _isRunning = false;
    _isPaused = false;
    notifyListeners();
  }

  /// Resets all step statuses to pending.
  void reset() {
    cancel();
    for (int i = 0; i < _steps.length; i++) {
      _steps[i] = _steps[i].copyWith(
        status: .pending,
        output: null,
        errorMessage: null,
        startTime: null,
        endTime: null,
      );
    }
    _currentError = null;
    _currentStepIndex = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
