/// Shared utility and helper APIs for ADK runtime behavior.
library;

import '../agents/context.dart';
import '../agents/invocation_context.dart';
import '../agents/readonly_context.dart';
import '../events/event.dart';
import '../flows/llm_flows/base_llm_flow.dart';
import '../flows/llm_flows/functions.dart' as flow_functions;
import '../models/llm_request.dart';
import '../sessions/state.dart';
import '../tools/base_tool.dart';
import '../types/content.dart';
import 'auth_resume.dart';
import 'auth_tool.dart';

/// Handles auth responses and resumes paused tool calls after credential input.
class AuthLlmRequestProcessor extends BaseLlmRequestProcessor {
  @override
  Stream<Event> runAsync(InvocationContext context, LlmRequest request) async* {
    final List<Event> events = context.getEvents(currentBranch: true);
    if (events.isEmpty) {
      return;
    }

    final Event? lastWithContent = _findLastEventWithContent(events);
    if (lastWithContent == null || lastWithContent.author != 'user') {
      return;
    }

    final List<FunctionResponse> authResponses = lastWithContent
        .getFunctionResponses()
        .where(
          (FunctionResponse response) =>
              response.name == flow_functions.requestEucFunctionCallName,
        )
        .toList(growable: false);
    if (authResponses.isEmpty) {
      return;
    }

    final Set<String> authFcIds = <String>{};
    final Map<String, Object?> authResponsePayloads = <String, Object?>{};
    for (final FunctionResponse response in authResponses) {
      final String? requestId = response.id;
      if (requestId == null || requestId.isEmpty) {
        continue;
      }
      authFcIds.add(requestId);
      authResponsePayloads[requestId] = response.response;
    }
    if (authFcIds.isEmpty) {
      return;
    }

    final Set<String> toolsToResume = await _storeAuthAndCollectResumeTargets(
      events: events,
      authFcIds: authFcIds,
      authResponses: authResponsePayloads,
      state: Context(context).state,
    );
    if (toolsToResume.isEmpty) {
      return;
    }

    final Map<String, BaseTool> toolsDict = await _buildToolsDict(context);
    if (toolsDict.isEmpty) {
      return;
    }

    for (int i = events.length - 1; i >= 0; i -= 1) {
      final Event event = events[i];
      final bool hasMatchingCall = event.getFunctionCalls().any(
        (FunctionCall call) =>
            call.id != null && toolsToResume.contains(call.id!),
      );
      if (!hasMatchingCall) {
        continue;
      }
      if (event.author != context.agent.name) {
        continue;
      }

      final Event? resumed = await flow_functions.handleFunctionCallsAsync(
        context,
        event,
        toolsDict,
        filters: toolsToResume,
      );
      if (resumed != null) {
        yield resumed;
      }
      return;
    }
  }

  Future<Set<String>> _storeAuthAndCollectResumeTargets({
    required List<Event> events,
    required Set<String> authFcIds,
    required Map<String, Object?> authResponses,
    required State state,
  }) async {
    final Map<String, AuthToolArguments> requestedById =
        findRequestedAuthConfigs(events, authFcIds);

    final Set<String> authorizedKeys = <String>{};
    for (final String fcId in authFcIds) {
      if (!authResponses.containsKey(fcId)) {
        continue;
      }
      final AuthToolArguments? requestedArgs = requestedById[fcId];
      if (requestedArgs == null) {
        continue;
      }
      final AuthConfig? storedConfig = await storeAuthResponse(
        requested: requestedArgs.authConfig,
        response: authResponses[fcId],
        state: state,
        interruptId: fcId,
      );
      if (storedConfig != null && storedConfig.credentialKey.isNotEmpty) {
        authorizedKeys.add(storedConfig.credentialKey);
      }
    }

    final Set<String> toolsToResume = <String>{};
    for (final AuthToolArguments requestedArgs in requestedById.values) {
      final String functionCallId = requestedArgs.functionCallId;
      if (functionCallId.isNotEmpty &&
          !functionCallId.startsWith(toolsetAuthCredentialIdPrefix)) {
        toolsToResume.add(functionCallId);
      }
    }

    final List<Event> matchingEvents = <Event>[];
    for (final Event event in events) {
      final Map<String, Object> requestedConfigs =
          event.actions.requestedAuthConfigs;
      if (requestedConfigs.isNotEmpty &&
          toolsToResume.any(requestedConfigs.containsKey)) {
        matchingEvents.add(event);
      }
    }

    for (final Event event in matchingEvents) {
      for (final MapEntry<String, Object> entry
          in event.actions.requestedAuthConfigs.entries) {
        try {
          final AuthConfig config = parseAuthConfigPayload(entry.value);
          if (authorizedKeys.contains(config.credentialKey)) {
            toolsToResume.add(entry.key);
          }
        } on ArgumentError {
          continue;
        }
      }
    }

    return toolsToResume;
  }

  Event? _findLastEventWithContent(List<Event> events) {
    for (int i = events.length - 1; i >= 0; i -= 1) {
      final Event event = events[i];
      if (event.content != null) {
        return event;
      }
    }
    return null;
  }

  Future<Map<String, BaseTool>> _buildToolsDict(
    InvocationContext context,
  ) async {
    final dynamic agent = context.agent;
    try {
      final Object? toolsRaw = await agent.canonicalTools(
        ReadonlyContext(context),
      );
      if (toolsRaw is! List) {
        return <String, BaseTool>{};
      }

      final Map<String, BaseTool> dict = <String, BaseTool>{};
      for (final Object? item in toolsRaw) {
        if (item is BaseTool) {
          dict[item.name] = item;
        }
      }
      return dict;
    } catch (_) {
      return <String, BaseTool>{};
    }
  }
}
