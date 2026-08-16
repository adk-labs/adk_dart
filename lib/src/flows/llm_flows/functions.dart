/// LLM flow pipeline components and processors.
library;

import 'dart:async';
import 'dart:convert';

import '../../agents/context.dart';
import '../../agents/invocation_context.dart';
import '../../agents/run_config.dart';
import '../../auth/auth_tool.dart';
import '../../events/event.dart';
import '../../events/event_actions.dart';
import '../../tools/base_tool.dart';
import '../../tools/computer_use/computer_use_tool.dart';
import '../../tools/tool_confirmation.dart';
import '../../tools/tool_context.dart';
import '../../types/content.dart';
import '../../types/id.dart';
import '../../agents/llm_agent.dart';

/// Prefix for ADK-generated client-side function call identifiers.
const String afFunctionCallIdPrefix = 'adk-';

/// Internal function name used to request credentials.
const String requestEucFunctionCallName = 'adk_request_credential';

/// Internal function name used to request tool confirmation.
const String requestConfirmationFunctionCallName = 'adk_request_confirmation';

/// Internal function name used to request additional user input.
const String requestInputFunctionCallName = 'adk_request_input';

/// Generates a new ADK client function-call identifier.
String generateClientFunctionCallId() {
  return newAdkId(prefix: afFunctionCallIdPrefix);
}

/// Populates missing function-call IDs on [modelResponseEvent].
void populateClientFunctionCallId(Event modelResponseEvent) {
  final List<FunctionCall> calls = modelResponseEvent.getFunctionCalls();
  if (calls.isEmpty) {
    return;
  }
  for (final FunctionCall call in calls) {
    call.id ??= generateClientFunctionCallId();
  }
}

/// Removes ADK-generated client IDs from [content] for backend calls.
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

/// Returns IDs of long-running tool calls in [functionCalls].
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

/// Builds an auth request event from [functionResponseEvent], when needed.
Event? generateAuthEvent(
  InvocationContext invocationContext,
  Event functionResponseEvent,
) {
  if (functionResponseEvent.actions.requestedAuthConfigs.isEmpty) {
    return null;
  }

  final Map<String, AuthConfig> authRequests = <String, AuthConfig>{};
  functionResponseEvent.actions.requestedAuthConfigs.forEach((
    String functionCallId,
    Object authConfig,
  ) {
    if (authConfig is AuthConfig) {
      authRequests[functionCallId] = authConfig;
    }
  });
  if (authRequests.isEmpty) {
    return null;
  }

  return buildAuthRequestEvent(
    invocationContext,
    authRequests,
    role: functionResponseEvent.content?.role,
  );
}

/// Builds an auth request event for [authRequests].
Event buildAuthRequestEvent(
  InvocationContext invocationContext,
  Map<String, AuthConfig> authRequests, {
  String? author,
  String? role,
}) {
  final List<Part> parts = <Part>[];
  final Set<String> longRunningIds = <String>{};

  authRequests.forEach((String functionCallId, AuthConfig authConfig) {
    final String id = generateClientFunctionCallId();
    longRunningIds.add(id);
    parts.add(
      Part.fromFunctionCall(
        name: requestEucFunctionCallName,
        id: id,
        args: AuthToolArguments(
          functionCallId: functionCallId,
          authConfig: authConfig,
        ).toJson(),
      ),
    );
  });

  return Event(
    invocationId: invocationContext.invocationId,
    author: author ?? invocationContext.agent.name,
    branch: invocationContext.branch,
    content: Content(role: role, parts: parts),
    longRunningToolIds: longRunningIds,
  );
}

/// Builds a tool-confirmation request event, when requested.
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

/// Handles function calls attached to [functionCallEvent].
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

/// Handles a list of [functionCalls] and returns a merged response event.
Future<Event?> handleFunctionCallListAsync(
  InvocationContext invocationContext,
  List<FunctionCall> functionCalls,
  Map<String, BaseTool> toolsDict, {
  Set<String>? filters,
  Map<String, ToolConfirmation>? toolConfirmationDict,
}) async {
  if (invocationContext.isAborted) {
    return null;
  }

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

  final List<Event?> results = <Event?>[];
  if (invocationContext.runConfig?.toolExecutionMode ==
      ToolExecutionMode.sequential) {
    for (final FunctionCall call in filtered) {
      if (invocationContext.isAborted) {
        return null;
      }
      results.add(
        await _executeSingleFunctionCallAsync(
          invocationContext,
          call,
          toolsDict,
          agent,
          toolConfirmation: call.id == null
              ? null
              : toolConfirmationDict?[call.id!],
        ),
      );
    }
  } else {
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

    results.addAll(await Future.wait(tasks, eagerError: true));
  }
  if (invocationContext.isAborted) {
    return null;
  }
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
  if (invocationContext.isAborted) {
    return null;
  }

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

  if (invocationContext.liveRequestQueue != null &&
      (tool.responseScheduling == FunctionResponseScheduling.whenIdle ||
          tool.responseScheduling == FunctionResponseScheduling.silent)) {
    final String taskKey =
        '${tool.name}_${functionCall.id ?? generateClientFunctionCallId()}';
    invocationContext.activeNonBlockingToolTasks ??= <String, Future<void>>{};

    final Completer<void> taskCompleter = Completer<void>();
    invocationContext.activeNonBlockingToolTasks![taskKey] =
        taskCompleter.future;

    unawaited(() async {
      try {
        final Event? responseEvent = await _runToolExecutionPipeline(
          invocationContext: invocationContext,
          functionCall: functionCall,
          functionArgs: functionArgs,
          tool: tool,
          toolContext: toolContext,
          agent: agent,
        );
        if (responseEvent?.content != null &&
            invocationContext.liveRequestQueue != null) {
          final Content responseContent = responseEvent!.content!.copyWith();
          for (final Part part in responseContent.parts) {
            if (part.functionResponse != null) {
              part.functionResponse!.scheduling = tool.responseScheduling;
            }
          }
          invocationContext.liveRequestQueue!.sendContent(responseContent);
        }
      } catch (_) {
      } finally {
        invocationContext.activeNonBlockingToolTasks?.remove(taskKey);
        if (!taskCompleter.isCompleted) {
          taskCompleter.complete();
        }
      }
    }());

    return null;
  }

  return _runToolExecutionPipeline(
    invocationContext: invocationContext,
    functionCall: functionCall,
    functionArgs: functionArgs,
    tool: tool,
    toolContext: toolContext,
    agent: agent,
  );
}

Future<Event?> _runToolExecutionPipeline({
  required InvocationContext invocationContext,
  required FunctionCall functionCall,
  required Map<String, dynamic> functionArgs,
  required BaseTool tool,
  required ToolContext toolContext,
  required LlmAgent agent,
}) async {
  Map<String, dynamic>? functionResponse = await invocationContext.pluginManager
      .runBeforeToolCallback(
        tool: tool,
        toolArgs: functionArgs,
        toolContext: toolContext,
      );
  if (invocationContext.isAborted) {
    return null;
  }

  Object? rawResult = functionResponse;

  if (functionResponse == null) {
    for (final BeforeToolCallback callback
        in agent.canonicalBeforeToolCallbacks) {
      if (invocationContext.isAborted) {
        return null;
      }
      final Map<String, dynamic>? value =
          await Future<Map<String, dynamic>?>.value(
            callback(tool, functionArgs, toolContext),
          );
      if (invocationContext.isAborted) {
        return null;
      }
      if (value != null) {
        functionResponse = value;
        rawResult = value;
        break;
      }
    }
  }

  if (functionResponse == null) {
    try {
      if (invocationContext.isAborted) {
        return null;
      }
      final Object? result = await tool.run(
        args: functionArgs,
        toolContext: toolContext,
      );
      if (invocationContext.isAborted) {
        return null;
      }
      rawResult = result;
      functionResponse = tool.defersResponse && result == null
          ? <String, dynamic>{}
          : _normalizeFunctionResult(result);
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
      rawResult = handled;
    }
  }

  Map<String, dynamic>? altered = await invocationContext.pluginManager
      .runAfterToolCallback(
        tool: tool,
        toolArgs: functionArgs,
        toolContext: toolContext,
        result: functionResponse,
      );
  if (invocationContext.isAborted) {
    return null;
  }

  if (altered == null) {
    for (final AfterToolCallback callback
        in agent.canonicalAfterToolCallbacks) {
      if (invocationContext.isAborted) {
        return null;
      }
      final Map<String, dynamic>? value =
          await Future<Map<String, dynamic>?>.value(
            callback(tool, functionArgs, toolContext, functionResponse),
          );
      if (invocationContext.isAborted) {
        return null;
      }
      if (value != null) {
        altered = value;
        break;
      }
    }
  }

  if (altered != null) {
    functionResponse = altered;
  }

  if ((tool.isLongRunning || tool.defersResponse) && functionResponse.isEmpty) {
    return null;
  }

  return _buildResponseEvent(
    tool: tool,
    functionResult: functionResponse,
    toolContext: toolContext,
    invocationContext: invocationContext,
    rawResult: rawResult,
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
  if (invocationContext.isAborted) {
    return null;
  }

  final Map<String, dynamic>? pluginHandled = await invocationContext
      .pluginManager
      .runOnToolErrorCallback(
        tool: tool,
        toolArgs: toolArgs,
        toolContext: toolContext,
        error: error,
      );
  if (invocationContext.isAborted) {
    return null;
  }
  if (pluginHandled != null) {
    return pluginHandled;
  }

  for (final OnToolErrorCallback callback
      in agent.canonicalOnToolErrorCallbacks) {
    if (invocationContext.isAborted) {
      return null;
    }
    final Map<String, dynamic>? value =
        await Future<Map<String, dynamic>?>.value(
          callback(tool, toolArgs, toolContext, error),
        );
    if (invocationContext.isAborted) {
      return null;
    }
    if (value != null) {
      return value;
    }
  }

  return null;
}

/// Resolves [functionCall] to a tool instance from [toolsDict].
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

(Object?, List<Part>?) _extractMultimodalParts(Object? functionResult) {
  if (functionResult is Part) {
    if (functionResult.inlineData != null) {
      return (<String, dynamic>{}, <Part>[functionResult]);
    }
  }

  if (functionResult is Map) {
    final Map<String, dynamic> keptItems = <String, dynamic>{};
    final List<Part> parts = <Part>[];
    for (final MapEntry<Object?, Object?> entry in functionResult.entries) {
      final Object? value = entry.value;
      if (value is Part && value.inlineData != null) {
        parts.add(value);
      } else {
        keptItems['${entry.key}'] = value;
      }
    }
    if (parts.isNotEmpty) {
      return (keptItems, parts);
    }
  } else if (functionResult is List) {
    final List<Object?> keptValues = <Object?>[];
    final List<Part> parts = <Part>[];
    for (final Object? value in functionResult) {
      if (value is Part && value.inlineData != null) {
        parts.add(value);
      } else {
        keptValues.add(value);
      }
    }
    if (parts.isNotEmpty) {
      return (keptValues, parts);
    }
  }

  return (functionResult, null);
}

/// Builds a user-role function response event from tool execution output.
Event _buildResponseEvent({
  required BaseTool tool,
  required Map<String, dynamic> functionResult,
  required ToolContext toolContext,
  required InvocationContext invocationContext,
  Object? rawResult,
}) {
  final (Object? remainingResult, List<Part>? extractedParts) =
      _extractMultimodalParts(rawResult ?? functionResult);
  final Map<String, dynamic> normalizedResult =
      _normalizeFunctionResult(remainingResult);

  final Object? displayResult = rawResult ?? normalizedResult;
  final Part functionResponsePart = Part.fromFunctionResponse(
    name: tool.name,
    response: normalizedResult,
    id: toolContext.functionCallId,
    parts: extractedParts,
  );
  final Part? imagePart = _decodeComputerUseImagePart(tool, normalizedResult);
  final List<Part> parts = <Part>[functionResponsePart, ?imagePart];

  // When summarization is skipped, ensure a displayable text part is added so
  // the tool's output is not lost in UIs that don't render function responses.
  // Control-flow tools (e.g. exit_loop) set skipSummarization but return no
  // meaningful output; their null result is normalized to {'result': null}, so
  // skip those to avoid emitting a noisy "null" text part.
  final bool hasDisplayableResult = displayResult != null &&
      !(displayResult is Map &&
          displayResult.length == 1 &&
          displayResult.containsKey('result') &&
          displayResult['result'] == null);

  if (toolContext.actions.skipSummarization == true &&
      !functionResult.containsKey('error') &&
      hasDisplayableResult) {
    String resultText;
    if (displayResult is String) {
      resultText = displayResult;
    } else {
      try {
        resultText = jsonEncode(displayResult);
      } catch (_) {
        resultText = '$displayResult';
      }
    }
    parts.add(Part.text(resultText));
  }

  return Event(
    invocationId: invocationContext.invocationId,
    author: invocationContext.agent.name,
    branch: invocationContext.branch,
    content: Content(role: 'user', parts: parts),
    actions: toolContext.actions,
  );
}

Part? _decodeComputerUseImagePart(
  BaseTool tool,
  Map<String, dynamic> functionResult,
) {
  if (tool is! ComputerUseTool) {
    return null;
  }
  final Object? imageObject = functionResult['image'];
  if (imageObject is! Map) {
    return null;
  }

  final Map<String, Object?> image = imageObject.map(
    (Object? key, Object? value) => MapEntry('$key', value),
  );
  final Object? encoded = image['data'];
  final Object? mimeType =
      image['mimetype'] ?? image['mimeType'] ?? image['mime_type'];
  if (encoded is! String || encoded.isEmpty || mimeType == null) {
    return null;
  }

  try {
    final List<int> bytes = base64Decode(encoded);
    functionResult.remove('image');
    return Part.fromInlineData(mimeType: '$mimeType', data: bytes);
  } catch (_) {
    return null;
  }
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

/// Merges multiple parallel function response events into one event.
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

    _deepMergeStateDelta(mergedActions.stateDelta, event.actions.stateDelta);
    mergedActions.artifactDelta.addAll(event.actions.artifactDelta);
    mergedActions.requestedAuthConfigs.addAll(
      event.actions.requestedAuthConfigs,
    );
    mergedActions.requestedToolConfirmations.addAll(
      event.actions.requestedToolConfirmations,
    );
    mergedActions.renderUiWidgets.addAll(
      event.actions.renderUiWidgets.map((widget) => widget.copyWith()),
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

void _deepMergeStateDelta(
  Map<String, Object?> target,
  Map<String, Object?> source,
) {
  source.forEach((String key, Object? value) {
    final Object? existing = target[key];
    if (existing is Map && value is Map) {
      final Map<String, Object?> nested = existing.map(
        (Object? nestedKey, Object? nestedValue) =>
            MapEntry('$nestedKey', nestedValue),
      );
      _deepMergeStateDelta(
        nested,
        value.map(
          (Object? nestedKey, Object? nestedValue) =>
              MapEntry('$nestedKey', nestedValue),
        ),
      );
      target[key] = nested;
      return;
    }
    if (existing is List && value is List) {
      target[key] = <Object?>[...existing, ...value];
      return;
    }
    target[key] = value;
  });
}

/// Finds the originating function-call event for the latest response event.
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

/// Placeholder tool used to surface missing-tool errors through callbacks.
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
