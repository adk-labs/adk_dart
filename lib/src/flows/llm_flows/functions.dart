import 'dart:async';

import '../../agents/context.dart';
import '../../agents/invocation_context.dart';
import '../../events/event.dart';
import '../../events/event_actions.dart';
import '../../tools/base_tool.dart';
import '../../tools/tool_confirmation.dart';
import '../../tools/tool_context.dart';
import '../../types/content.dart';
import '../../types/id.dart';
import '../../agents/llm_agent.dart';

const String afFunctionCallIdPrefix = 'adk-';
const String requestEucFunctionCallName = 'adk_request_credential';
const String requestConfirmationFunctionCallName = 'adk_request_confirmation';
const String requestInputFunctionCallName = 'adk_request_input';

String generateClientFunctionCallId() {
  return newAdkId(prefix: afFunctionCallIdPrefix);
}

void populateClientFunctionCallId(Event modelResponseEvent) {
  final List<FunctionCall> calls = modelResponseEvent.getFunctionCalls();
  if (calls.isEmpty) {
    return;
  }
  for (final FunctionCall call in calls) {
    call.id ??= generateClientFunctionCallId();
  }
}

void removeClientFunctionCallId(Content? content) {
  if (content == null) {
    return;
  }

  for (final Part part in content.parts) {
    if (part.functionCall?.id?.startsWith(afFunctionCallIdPrefix) == true) {
      part.functionCall!.id = null;
    }
    if (part.functionResponse?.id?.startsWith(afFunctionCallIdPrefix) == true) {
      part.functionResponse!.id = null;
    }
  }
}

Set<String> getLongRunningFunctionCalls(
  List<FunctionCall> functionCalls,
  Map<String, BaseTool> toolsDict,
) {
  final Set<String> ids = <String>{};
  for (final FunctionCall call in functionCalls) {
    final BaseTool? tool = toolsDict[call.name];
    if (tool != null && tool.isLongRunning && call.id != null) {
      ids.add(call.id!);
    }
  }
  return ids;
}

Event? generateAuthEvent(
  InvocationContext invocationContext,
  Event functionResponseEvent,
) {
  if (functionResponseEvent.actions.requestedAuthConfigs.isEmpty) {
    return null;
  }

  final List<Part> parts = <Part>[];
  final Set<String> longRunningIds = <String>{};
  functionResponseEvent.actions.requestedAuthConfigs.forEach((
    String functionCallId,
    Object authConfig,
  ) {
    final String id = generateClientFunctionCallId();
    longRunningIds.add(id);
    parts.add(
      Part.fromFunctionCall(
        name: requestEucFunctionCallName,
        id: id,
        args: <String, dynamic>{
          'function_call_id': functionCallId,
          'auth_config': authConfig,
        },
      ),
    );
  });

  return Event(
    invocationId: invocationContext.invocationId,
    author: invocationContext.agent.name,
    branch: invocationContext.branch,
    content: Content(role: 'user', parts: parts),
    longRunningToolIds: longRunningIds,
  );
}

Event? generateRequestConfirmationEvent(
  InvocationContext invocationContext,
  Event functionCallEvent,
  Event functionResponseEvent,
) {
  if (functionResponseEvent.actions.requestedToolConfirmations.isEmpty) {
    return null;
  }

  final List<Part> parts = <Part>[];
  final Set<String> longRunningIds = <String>{};
  final List<FunctionCall> calls = functionCallEvent.getFunctionCalls();

  functionResponseEvent.actions.requestedToolConfirmations.forEach((
    String functionCallId,
    Object confirmation,
  ) {
    final FunctionCall? original = calls
        .where((FunctionCall call) => call.id == functionCallId)
        .cast<FunctionCall?>()
        .firstWhere((FunctionCall? call) => call != null, orElse: () => null);
    if (original == null) {
      return;
    }

    final String id = generateClientFunctionCallId();
    longRunningIds.add(id);
    parts.add(
      Part.fromFunctionCall(
        name: requestConfirmationFunctionCallName,
        id: id,
        args: <String, dynamic>{
          'originalFunctionCall': <String, dynamic>{
            'name': original.name,
            'id': original.id,
            'args': Map<String, dynamic>.from(original.args),
          },
          'toolConfirmation': confirmation,
        },
      ),
    );
  });

  return Event(
    invocationId: invocationContext.invocationId,
    author: invocationContext.agent.name,
    branch: invocationContext.branch,
    content: Content(role: functionResponseEvent.content?.role, parts: parts),
    longRunningToolIds: longRunningIds,
  );
}

Future<Event?> handleFunctionCallsAsync(
  InvocationContext invocationContext,
  Event functionCallEvent,
  Map<String, BaseTool> toolsDict, {
  Set<String>? filters,
  Map<String, ToolConfirmation>? toolConfirmationDict,
}) async {
  final List<FunctionCall> calls = functionCallEvent.getFunctionCalls();
  return handleFunctionCallListAsync(
    invocationContext,
    calls,
    toolsDict,
    filters: filters,
    toolConfirmationDict: toolConfirmationDict,
  );
}

Future<Event?> handleFunctionCallListAsync(
  InvocationContext invocationContext,
  List<FunctionCall> functionCalls,
  Map<String, BaseTool> toolsDict, {
  Set<String>? filters,
  Map<String, ToolConfirmation>? toolConfirmationDict,
}) async {
  final List<FunctionCall> filtered = functionCalls
      .where(
        (FunctionCall call) =>
            filters == null || (call.id != null && filters.contains(call.id)),
      )
      .toList();

  if (filtered.isEmpty) {
    return null;
  }

  final LlmAgent agent = invocationContext.agent as LlmAgent;

  final List<Future<Event?>> tasks = filtered.map((FunctionCall call) {
    return _executeSingleFunctionCallAsync(
      invocationContext,
      call,
      toolsDict,
      agent,
      toolConfirmation: call.id == null
          ? null
          : toolConfirmationDict?[call.id!],
    );
  }).toList();

  final List<Event?> results = await Future.wait(tasks);
  final List<Event> events = results.whereType<Event>().toList(growable: false);

  if (events.isEmpty) {
    return null;
  }

  return mergeParallelFunctionResponseEvents(events);
}

Future<Event?> _executeSingleFunctionCallAsync(
  InvocationContext invocationContext,
  FunctionCall functionCall,
  Map<String, BaseTool> toolsDict,
  LlmAgent agent, {
  ToolConfirmation? toolConfirmation,
}) async {
  final Map<String, dynamic> functionArgs = Map<String, dynamic>.from(
    functionCall.args,
  );

  final ToolContext toolContext = Context(
    invocationContext,
    functionCallId: functionCall.id,
    toolConfirmation: toolConfirmation,
  );

  BaseTool tool;
  try {
    tool = _getTool(functionCall, toolsDict);
  } catch (error) {
    final Exception exception = error is Exception
        ? error
        : Exception(error.toString());
    final BaseTool missing = _MissingTool(functionCall.name);

    final Map<String, dynamic>? onError = await _runOnToolErrorCallbacks(
      invocationContext: invocationContext,
      agent: agent,
      tool: missing,
      toolArgs: functionArgs,
      toolContext: toolContext,
      error: exception,
    );

    if (onError == null) {
      rethrow;
    }

    return _buildResponseEvent(
      tool: missing,
      functionResult: onError,
      toolContext: toolContext,
      invocationContext: invocationContext,
    );
  }

  Map<String, dynamic>? functionResponse = await invocationContext.pluginManager
      .runBeforeToolCallback(
        tool: tool,
        toolArgs: functionArgs,
        toolContext: toolContext,
      );

  if (functionResponse == null) {
    for (final BeforeToolCallback callback
        in agent.canonicalBeforeToolCallbacks) {
      final Map<String, dynamic>? value =
          await Future<Map<String, dynamic>?>.value(
            callback(tool, functionArgs, toolContext),
          );
      if (value != null) {
        functionResponse = value;
        break;
      }
    }
  }

  if (functionResponse == null) {
    try {
      final Object? result = await tool.run(
        args: functionArgs,
        toolContext: toolContext,
      );
      functionResponse = _normalizeFunctionResult(result);
    } catch (error) {
      final Exception exception = error is Exception
          ? error
          : Exception(error.toString());
      final Map<String, dynamic>? handled = await _runOnToolErrorCallbacks(
        invocationContext: invocationContext,
        agent: agent,
        tool: tool,
        toolArgs: functionArgs,
        toolContext: toolContext,
        error: exception,
      );
      if (handled == null) {
        rethrow;
      }
      functionResponse = handled;
    }
  }

  Map<String, dynamic>? altered = await invocationContext.pluginManager
      .runAfterToolCallback(
        tool: tool,
        toolArgs: functionArgs,
        toolContext: toolContext,
        result: functionResponse,
      );

  if (altered == null) {
    for (final AfterToolCallback callback
        in agent.canonicalAfterToolCallbacks) {
      final Map<String, dynamic>? value =
          await Future<Map<String, dynamic>?>.value(
            callback(tool, functionArgs, toolContext, functionResponse),
          );
      if (value != null) {
        altered = value;
        break;
      }
    }
  }

  if (altered != null) {
    functionResponse = altered;
  }

  if (tool.isLongRunning && functionResponse.isEmpty) {
    return null;
  }

  return _buildResponseEvent(
    tool: tool,
    functionResult: functionResponse,
    toolContext: toolContext,
    invocationContext: invocationContext,
  );
}

Future<Map<String, dynamic>?> _runOnToolErrorCallbacks({
  required InvocationContext invocationContext,
  required LlmAgent agent,
  required BaseTool tool,
  required Map<String, dynamic> toolArgs,
  required ToolContext toolContext,
  required Exception error,
}) async {
  final Map<String, dynamic>? pluginHandled = await invocationContext
      .pluginManager
      .runOnToolErrorCallback(
        tool: tool,
        toolArgs: toolArgs,
        toolContext: toolContext,
        error: error,
      );
  if (pluginHandled != null) {
    return pluginHandled;
  }

  for (final OnToolErrorCallback callback
      in agent.canonicalOnToolErrorCallbacks) {
    final Map<String, dynamic>? value =
        await Future<Map<String, dynamic>?>.value(
          callback(tool, toolArgs, toolContext, error),
        );
    if (value != null) {
      return value;
    }
  }

  return null;
}

BaseTool _getTool(FunctionCall functionCall, Map<String, BaseTool> toolsDict) {
  final BaseTool? tool = toolsDict[functionCall.name];
  if (tool == null) {
    final String available = toolsDict.keys.join(', ');
    throw StateError(
      "Tool '${functionCall.name}' not found. Available tools: $available",
    );
  }
  return tool;
}

Event _buildResponseEvent({
  required BaseTool tool,
  required Map<String, dynamic> functionResult,
  required ToolContext toolContext,
  required InvocationContext invocationContext,
}) {
  final Part part = Part.fromFunctionResponse(
    name: tool.name,
    response: functionResult,
    id: toolContext.functionCallId,
  );

  return Event(
    invocationId: invocationContext.invocationId,
    author: invocationContext.agent.name,
    branch: invocationContext.branch,
    content: Content(role: 'user', parts: <Part>[part]),
    actions: toolContext.actions,
  );
}

Map<String, dynamic> _normalizeFunctionResult(Object? result) {
  if (result is Map<String, dynamic>) {
    return result;
  }

  if (result is Map) {
    return Map<String, dynamic>.from(result);
  }

  return <String, dynamic>{'result': result};
}

Event mergeParallelFunctionResponseEvents(List<Event> functionResponseEvents) {
  if (functionResponseEvents.isEmpty) {
    throw ArgumentError('No function response events provided.');
  }

  if (functionResponseEvents.length == 1) {
    return functionResponseEvents.first;
  }

  final Event base = functionResponseEvents.first;
  final List<Part> mergedParts = <Part>[];
  final EventActions mergedActions = EventActions();

  for (final Event event in functionResponseEvents) {
    final Content? content = event.content;
    if (content != null) {
      mergedParts.addAll(content.parts.map((Part part) => part.copyWith()));
    }

    mergedActions.stateDelta.addAll(event.actions.stateDelta);
    mergedActions.artifactDelta.addAll(event.actions.artifactDelta);
    mergedActions.requestedAuthConfigs.addAll(
      event.actions.requestedAuthConfigs,
    );
    mergedActions.requestedToolConfirmations.addAll(
      event.actions.requestedToolConfirmations,
    );

    if (event.actions.transferToAgent != null) {
      mergedActions.transferToAgent = event.actions.transferToAgent;
    }
    if (event.actions.escalate != null) {
      mergedActions.escalate = event.actions.escalate;
    }
    if (event.actions.skipSummarization != null) {
      mergedActions.skipSummarization = event.actions.skipSummarization;
    }
    if (event.actions.compaction != null) {
      mergedActions.compaction = event.actions.compaction;
    }
    if (event.actions.endOfAgent != null) {
      mergedActions.endOfAgent = event.actions.endOfAgent;
    }
    if (event.actions.agentState != null) {
      mergedActions.agentState = Map<String, Object?>.from(
        event.actions.agentState!,
      );
    }
    if (event.actions.rewindBeforeInvocationId != null) {
      mergedActions.rewindBeforeInvocationId =
          event.actions.rewindBeforeInvocationId;
    }
  }

  final Event merged = Event(
    invocationId: base.invocationId,
    author: base.author,
    branch: base.branch,
    content: Content(role: 'user', parts: mergedParts),
    actions: mergedActions,
  );

  merged.timestamp = base.timestamp;
  return merged;
}

Event? findMatchingFunctionCall(List<Event> events) {
  if (events.isEmpty) {
    return null;
  }

  final Event last = events.last;
  final List<FunctionResponse> responses = last.getFunctionResponses();
  if (responses.isEmpty) {
    return null;
  }

  final String? functionCallId = responses.first.id;
  if (functionCallId == null) {
    return null;
  }

  for (int i = events.length - 2; i >= 0; i -= 1) {
    final Event event = events[i];
    for (final FunctionCall call in event.getFunctionCalls()) {
      if (call.id == functionCallId) {
        return event;
      }
    }
  }

  return null;
}

class _MissingTool extends BaseTool {
  _MissingTool(String toolName)
    : super(name: toolName, description: 'Tool not found');

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) {
    throw StateError('Tool not found: $name');
  }
}
