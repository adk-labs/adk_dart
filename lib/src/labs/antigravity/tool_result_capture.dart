/// Tool result, tool error, and sub-agent call capture hooks for Antigravity.
library;

import 'dart:collection';

/// Originator of an Antigravity conversation step.
enum StepSource {
  /// Unspecified step source.
  unspecified,

  /// User-authored step.
  user,

  /// Model-authored step.
  model,

  /// System-authored step.
  system,

  /// Tool-authored step.
  tool,
}

/// Classification of an Antigravity conversation step.
enum StepType {
  /// Unspecified step type.
  unspecified,

  /// Model text response step.
  textResponse,

  /// Tool call step.
  toolCall,

  /// System message step.
  systemMessage,

  /// Unknown step type.
  unknown,
}

/// Execution status of an Antigravity conversation step.
enum StepStatus {
  /// Unspecified step status.
  unspecified,

  /// Step is currently active / streaming.
  active,

  /// Step completed normally.
  done,

  /// Step terminated with an error.
  error,
}

/// Session continuation mode for local Antigravity conversations.
enum SessionContinuationMode {
  /// Unspecified continuation mode.
  unspecified,

  /// Creates a new conversation or resumes an existing one if found.
  createOrResume,

  /// Requires an existing conversation to resume.
  resumeOnly,

  /// Always starts a fresh conversation.
  createNew,
}

/// Built-in Antigravity SDK tool names.
class BuiltinTools {
  const BuiltinTools._();

  /// Built-in tool name used to invoke a native sub-agent trajectory.
  static const String startSubagent = 'start_subagent';
}

/// Decision returned by a pre-tool hook.
class HookResult {
  const HookResult._(this.name);

  /// Hook decision name.
  final String name;

  /// Allows the intercepted tool call to proceed.
  static const HookResult allow = HookResult._('ALLOW');
}

/// Represents a tool call emitted inside an Antigravity [AntigravityStep].
class AntigravityToolCall {
  /// Creates an Antigravity tool call.
  const AntigravityToolCall({
    required this.name,
    this.args = const <String, Object?>{},
    this.id = '',
  });

  /// Name of the invoked tool.
  final String name;

  /// Arguments passed to the tool.
  final Map<String, Object?> args;

  /// Unique identifier for this tool call.
  final String id;
}

/// Alias for [AntigravityToolCall] matching the Antigravity SDK `ToolCall` type.
typedef ToolCall = AntigravityToolCall;

/// Represents a completed tool execution result from an Antigravity hook.
class AntigravityToolResult {
  /// Creates an Antigravity tool result.
  const AntigravityToolResult({
    this.name = '',
    this.id = '',
    this.stepId = 0,
    this.result,
    this.error = '',
  });

  /// Tool name.
  final String name;

  /// Tool call ID (empty for built-in tools correlated by [stepId]).
  final String id;

  /// Step index that initiated this tool call.
  final int stepId;

  /// Structured or scalar tool output.
  final Object? result;

  /// Error message if the tool reported an error.
  final String error;
}

/// Alias for [AntigravityToolResult] matching the Antigravity SDK `ToolResult` type.
typedef ToolResult = AntigravityToolResult;

/// Represents a failed tool execution error from an Antigravity hook.
class AntigravityToolError {
  /// Creates an Antigravity tool error.
  const AntigravityToolError({
    this.toolName = '',
    this.callId = '',
    this.stepId = 0,
    this.message = '',
  });

  /// Name of the tool that failed.
  final String toolName;

  /// Tool call ID (empty for built-in tools correlated by [stepId]).
  final String callId;

  /// Step index that initiated this tool call.
  final int stepId;

  /// Human-readable error message.
  final String message;
}

/// Alias for [AntigravityToolError] matching the Antigravity SDK `ToolError` type.
typedef ToolError = AntigravityToolError;

/// Represents one step in an Antigravity conversation stream or history.
class AntigravityStep {
  /// Creates an Antigravity step.
  const AntigravityStep({
    this.stepIndex = 0,
    this.source = StepSource.model,
    this.type = StepType.textResponse,
    this.status = StepStatus.done,
    this.content = '',
    this.thinking = '',
    this.contentDelta = '',
    this.thinkingDelta = '',
    this.isCompleteResponse = true,
    this.toolCalls = const <AntigravityToolCall>[],
    this.error = '',
    this.trajectoryId = '',
    this.parentTrajectoryId = '',
    this.depth = 0,
  });

  ///Zero-based or monotonic index of the step in the trajectory.
  final int stepIndex;

  /// Originator of the step.
  final StepSource source;

  /// High-level type of the step.
  final StepType type;

  /// Execution status of the step.
  final StepStatus status;

  /// Full accumulated text content of the step.
  final String content;

  /// Full accumulated thinking text of the step.
  final String thinking;

  /// Incremental text delta for streaming updates.
  final String contentDelta;

  /// Incremental thinking delta for streaming updates.
  final String thinkingDelta;

  /// Whether this step snapshot represents the complete response.
  final bool isCompleteResponse;

  /// Tool calls requested in this step.
  final List<AntigravityToolCall> toolCalls;

  /// Error message when [status] is [StepStatus.error].
  final String error;

  /// Identifier of the trajectory this step belongs to.
  final String trajectoryId;

  /// Identifier of the parent trajectory when emitted by a native sub-agent.
  final String parentTrajectoryId;

  /// Nesting depth of the trajectory (`0` for root).
  final int depth;
}

/// Alias for [AntigravityStep] matching the Antigravity SDK `Step` type.
typedef Step = AntigravityStep;

/// Token usage statistics recorded for an Antigravity turn.
class AntigravityTurnUsage {
  /// Creates turn usage statistics.
  const AntigravityTurnUsage({
    this.promptTokenCount = 0,
    this.candidatesTokenCount = 0,
    this.totalTokenCount = 0,
    this.thoughtsTokenCount = 0,
  });

  /// Number of tokens in the prompt.
  final int promptTokenCount;

  /// Number of tokens in the generated response candidates.
  final int candidatesTokenCount;

  /// Total tokens consumed in the turn.
  final int totalTokenCount;

  /// Number of tokens used for model thinking/reasoning.
  final int thoughtsTokenCount;
}

/// Shared buffer that correlates custom tool results (by call ID) and built-in
/// tool results (by `step_${stepId}`) back to ADK `FunctionCall` IDs.
///
/// ```dart
/// final buffer = ToolResultBuffer();
/// buffer.record(const AntigravityToolResult(
///   name: 'search',
///   id: 'call_1',
///   result: {'hits': 3},
/// ));
/// final drained = buffer.take(['call_1']);
/// ```
class ToolResultBuffer {
  /// Creates an empty tool result buffer.
  ToolResultBuffer();

  final Map<String, AntigravityToolResult> _byKey =
      <String, AntigravityToolResult>{};
  final Queue<Map<String, Object?>> _pendingSubagents =
      Queue<Map<String, Object?>>();

  /// Number of buffered tool results currently awaiting consumption.
  int get length => _byKey.length;

  /// FIFO queue of `start_subagent` tool call argument dictionaries.
  Queue<Map<String, Object?>> get pendingSubagents => _pendingSubagents;

  static String _keyFor(String callId, int stepId) {
    return callId.isNotEmpty ? callId : 'step_$stepId';
  }

  /// Records a `start_subagent` [call] for sub-agent trajectory attribution.
  void recordSubagent(AntigravityToolCall call) {
    if (call.name == BuiltinTools.startSubagent && call.args.isNotEmpty) {
      _pendingSubagents.add(Map<String, Object?>.from(call.args));
    }
  }

  /// Stores a successful or errored [result] in the buffer.
  void record(AntigravityToolResult result) {
    final String key = _keyFor(result.id, result.stepId);
    _byKey[key] = result;
  }

  /// Stores a tool failure [error] as a synthetic [AntigravityToolResult].
  void recordError(AntigravityToolError error) {
    final String key = _keyFor(error.callId, error.stepId);
    _byKey[key] = AntigravityToolResult(
      name: error.toolName,
      id: error.callId,
      stepId: error.stepId,
      result: null,
      error: error.message.isNotEmpty
          ? error.message
          : 'Tool execution failed',
    );
  }

  /// Pops and returns buffered results matching [callIds] in order.
  List<AntigravityToolResult> take(Iterable<String> callIds) {
    final List<AntigravityToolResult> out = <AntigravityToolResult>[];
    for (final String callId in callIds) {
      final AntigravityToolResult? removed = _byKey.remove(callId);
      if (removed != null) {
        out.add(removed);
      }
    }
    return out;
  }

  /// Clears all buffered tool results and pending sub-agent calls.
  void clear() {
    _byKey.clear();
    _pendingSubagents.clear();
  }
}

/// Post-tool hook that captures successful tool outputs into a [ToolResultBuffer].
class ToolResultCapture extends ToolResultBuffer {
  /// Creates a tool result capture hook.
  ToolResultCapture();

  /// Captures [data] into this buffer.
  Future<void> run(Object? context, AntigravityToolResult data) async {
    record(data);
  }
}

/// Post-tool-error hook that captures failed tool calls into a shared [ToolResultBuffer].
class ToolErrorCapture {
  /// Creates a tool error capture hook writing to [buffer].
  ToolErrorCapture(this.buffer);

  /// Shared buffer receiving captured tool errors.
  final ToolResultBuffer buffer;

  /// Captures [data] into [buffer] if it is an [AntigravityToolError].
  Future<void> run(Object? context, Object data) async {
    if (data is AntigravityToolError) {
      buffer.recordError(data);
    }
  }
}

/// Pre-tool hook that records `start_subagent` calls into a shared [ToolResultBuffer].
class SubagentCallCapture {
  /// Creates a sub-agent call capture hook writing to [buffer].
  SubagentCallCapture(this.buffer);

  /// Shared buffer receiving sub-agent call arguments.
  final ToolResultBuffer buffer;

  /// Records [data] if it invokes `start_subagent` and returns [HookResult.allow].
  Future<HookResult> run(Object? context, AntigravityToolCall data) async {
    buffer.recordSubagent(data);
    return HookResult.allow;
  }
}
