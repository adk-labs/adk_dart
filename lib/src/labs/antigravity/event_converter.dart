/// Converts Antigravity SDK steps and captured tool results into ADK [Event]s.
library;

import 'dart:developer' as developer;

import '../../agents/run_config.dart';
import '../../events/event.dart';
import '../../types/content.dart';
import 'tool_result_capture.dart';

const Map<String, String> _builtinOutputKeys = <String, String>{
  'run_command': 'combinedOutput',
  'find_file': 'result',
  'list_dir': 'directoryRelativePaths',
  'search_dir': 'result',
  'search_web': 'summary',
  'read_url_content': 'resolvedContent',
  'generate_image': 'generatedMediaPath',
  'edit_file': 'diff',
};

Object? _extractToolOutput(String toolName, Object? result) {
  if (result == null || result is String) {
    return result;
  }
  if (result is Map) {
    final String? key = _builtinOutputKeys[toolName];
    if (key != null && result.containsKey(key)) {
      return result[key];
    }
    return result;
  }
  return result;
}

Event _makeToolResponseEvent({
  required String invocationId,
  required String author,
  required String? branch,
  required List<AntigravityToolResult> results,
  required Map<String, String> idMap,
}) {
  final List<Part> parts = <Part>[];
  for (final AntigravityToolResult tr in results) {
    final String key = tr.id.isNotEmpty ? tr.id : 'step_${tr.stepId}';
    final String adkId = idMap[key] ?? key;
    final Map<String, dynamic> responsePayload = tr.error.isNotEmpty
        ? <String, dynamic>{'error': tr.error}
        : <String, dynamic>{'result': _extractToolOutput(tr.name, tr.result)};
    parts.add(
      Part.fromFunctionResponse(
        id: adkId,
        name: tr.name,
        response: responsePayload,
      ),
    );
  }
  return Event(
    invocationId: invocationId,
    author: author,
    branch: branch,
    content: Content(role: 'user', parts: parts),
  );
}

/// Drains buffered tool results matching [pendingFunctionCalls] and returns a
/// synthetic tool-response [Event], or `null` if no results are ready.
Event? drainToolResults({
  required String invocationId,
  required String author,
  String? branch,
  required List<FunctionCall> pendingFunctionCalls,
  required ToolResultBuffer resultBuffer,
}) {
  if (pendingFunctionCalls.isEmpty) {
    return null;
  }
  final List<String> callIds = <String>[
    for (final FunctionCall fc in pendingFunctionCalls)
      if (fc.id != null && fc.id!.isNotEmpty) fc.id!,
  ];
  final List<AntigravityToolResult> results = resultBuffer.take(callIds);
  pendingFunctionCalls.clear();
  if (results.isEmpty) {
    return null;
  }
  final Map<String, String> idMap = <String, String>{
    for (final AntigravityToolResult tr in results)
      (tr.id.isNotEmpty ? tr.id : 'step_${tr.stepId}'):
          (tr.id.isNotEmpty ? tr.id : 'step_${tr.stepId}'),
  };
  return _makeToolResponseEvent(
    invocationId: invocationId,
    author: author,
    branch: branch,
    results: results,
    idMap: idMap,
  );
}

/// Converts a single [AntigravityStep] into zero or more ADK [Event]s.
List<Event> convertStepToEvents(
  AntigravityStep step, {
  required String invocationId,
  required String author,
  String? branch,
  required List<FunctionCall> pendingFunctionCalls,
  required List<Part> pendingThoughts,
  required ToolResultBuffer resultBuffer,
  StreamingMode streamingMode = StreamingMode.none,
}) {
  if (step.source != StepSource.model) {
    return const <Event>[];
  }

  final List<Event> events = <Event>[];

  // Partial streaming step.
  if (step.status == StepStatus.active && !step.isCompleteResponse) {
    if (streamingMode != StreamingMode.sse) {
      return const <Event>[];
    }
    final Event? toolResp = drainToolResults(
      invocationId: invocationId,
      author: author,
      branch: branch,
      pendingFunctionCalls: pendingFunctionCalls,
      resultBuffer: resultBuffer,
    );
    if (toolResp != null) {
      events.add(toolResp);
    }

    final List<Part> parts = <Part>[];
    if (step.thinkingDelta.isNotEmpty) {
      parts.add(Part.text(step.thinkingDelta, thought: true));
    }
    if (step.contentDelta.isNotEmpty) {
      parts.add(Part.text(step.contentDelta));
    }
    if (parts.isNotEmpty) {
      events.add(
        Event(
          invocationId: invocationId,
          author: author,
          branch: branch,
          partial: true,
          content: Content(role: 'model', parts: parts),
        ),
      );
    }
    return events;
  }

  // Error step.
  if (step.status == StepStatus.error) {
    final Event? toolResp = drainToolResults(
      invocationId: invocationId,
      author: author,
      branch: branch,
      pendingFunctionCalls: pendingFunctionCalls,
      resultBuffer: resultBuffer,
    );
    if (toolResp != null) {
      events.add(toolResp);
    }
    if (pendingThoughts.isNotEmpty && step.content.isEmpty) {
      events.add(
        Event(
          invocationId: invocationId,
          author: author,
          branch: branch,
          content: Content(
            role: 'model',
            parts: List<Part>.from(pendingThoughts),
          ),
        ),
      );
      pendingThoughts.clear();
    }
    Content? content;
    if (step.content.isNotEmpty) {
      final List<Part> parts = <Part>[
        ...pendingThoughts,
        Part.text(step.content),
      ];
      pendingThoughts.clear();
      content = Content(role: 'model', parts: parts);
    }
    events.add(
      Event(
        invocationId: invocationId,
        author: author,
        branch: branch,
        errorCode: 'ANTIGRAVITY_STEP_ERROR',
        errorMessage: step.error.isNotEmpty
            ? step.error
            : 'Step ${step.stepIndex} failed',
        content: content,
      ),
    );
    return events;
  }

  // Tool call step.
  if (step.type == StepType.toolCall) {
    final Event? toolResp = drainToolResults(
      invocationId: invocationId,
      author: author,
      branch: branch,
      pendingFunctionCalls: pendingFunctionCalls,
      resultBuffer: resultBuffer,
    );
    if (toolResp != null) {
      events.add(toolResp);
    }

    final List<Part> parts = <Part>[...pendingThoughts];
    pendingThoughts.clear();
    if (step.thinking.isNotEmpty) {
      parts.add(Part.text(step.thinking, thought: true));
    }
    if (step.content.isNotEmpty) {
      parts.add(Part.text(step.content));
    }

    for (final AntigravityToolCall tc in step.toolCalls) {
      final String adkId = tc.id.isNotEmpty ? tc.id : 'step_${step.stepIndex}';
      final FunctionCall fc = FunctionCall(
        name: tc.name,
        args: Map<String, dynamic>.from(tc.args),
        id: adkId,
      );
      parts.add(Part(functionCall: fc));
      pendingFunctionCalls.add(fc);
    }

    if (parts.isNotEmpty) {
      events.add(
        Event(
          invocationId: invocationId,
          author: author,
          branch: branch,
          content: Content(role: 'model', parts: parts),
        ),
      );
    }
    return events;
  }

  // Text response step.
  if (step.type == StepType.textResponse) {
    if (pendingFunctionCalls.isNotEmpty) {
      if (step.thinking.isNotEmpty) {
        pendingThoughts.add(Part.text(step.thinking, thought: true));
      }
      return events;
    }

    final List<Part> parts = <Part>[...pendingThoughts];
    pendingThoughts.clear();
    if (step.thinking.isNotEmpty) {
      parts.add(Part.text(step.thinking, thought: true));
    }
    if (step.content.isNotEmpty) {
      parts.add(Part.text(step.content));
    }
    if (parts.isNotEmpty) {
      events.add(
        Event(
          invocationId: invocationId,
          author: author,
          branch: branch,
          content: Content(role: 'model', parts: parts),
        ),
      );
    }
    return events;
  }

  if (step.type != StepType.systemMessage && step.type != StepType.unknown) {
    developer.log(
      'Skipping unhandled StepType: ${step.type} (index=${step.stepIndex})',
      name: 'adk_dart.antigravity.event_converter',
    );
  }

  return events;
}

/// Converts a sequence of [AntigravityStep]s into ADK [Event]s and drains any
/// remaining buffered tool results or buffered thoughts.
List<Event> convertEventsToAdk(
  Iterable<AntigravityStep> steps, {
  required String invocationId,
  required String author,
  String? branch,
  List<FunctionCall>? pendingFunctionCalls,
  List<Part>? pendingThoughts,
  ToolResultBuffer? resultBuffer,
  StreamingMode streamingMode = StreamingMode.none,
}) {
  final List<FunctionCall> fcs = pendingFunctionCalls ?? <FunctionCall>[];
  final List<Part> thoughts = pendingThoughts ?? <Part>[];
  final ToolResultBuffer buffer = resultBuffer ?? ToolResultBuffer();
  final List<Event> events = <Event>[];

  for (final AntigravityStep step in steps) {
    events.addAll(
      convertStepToEvents(
        step,
        invocationId: invocationId,
        author: author,
        branch: branch,
        pendingFunctionCalls: fcs,
        pendingThoughts: thoughts,
        resultBuffer: buffer,
        streamingMode: streamingMode,
      ),
    );
  }

  final Event? trailingToolResp = drainToolResults(
    invocationId: invocationId,
    author: author,
    branch: branch,
    pendingFunctionCalls: fcs,
    resultBuffer: buffer,
  );
  if (trailingToolResp != null) {
    events.add(trailingToolResp);
  }
  if (thoughts.isNotEmpty) {
    events.add(
      Event(
        invocationId: invocationId,
        author: author,
        branch: branch,
        content: Content(role: 'model', parts: List<Part>.from(thoughts)),
      ),
    );
    thoughts.clear();
  }
  return events;
}

/// Extracts the final model text response from [steps], or `null` if none.
String? finalModelText(Iterable<AntigravityStep> steps) {
  final List<AntigravityStep> list = steps.toList(growable: false);
  for (int i = list.length - 1; i >= 0; i--) {
    final AntigravityStep step = list[i];
    if (step.source == StepSource.model &&
        step.type == StepType.textResponse &&
        step.content.isNotEmpty) {
      return step.content;
    }
  }
  return null;
}
