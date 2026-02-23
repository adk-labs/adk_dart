import 'dart:convert';

import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../agents/readonly_context.dart';
import '../../events/event.dart';
import '../../models/llm_request.dart';
import '../../tools/base_tool.dart';
import '../../tools/tool_confirmation.dart';
import '../../types/content.dart';
import 'base_llm_flow.dart';
import 'functions.dart' as flow_functions;

/// Resumes tool calls after user answers `adk_request_confirmation`.
class RequestConfirmationLlmRequestProcessor extends BaseLlmRequestProcessor {
  @override
  Stream<Event> runAsync(
    InvocationContext invocationContext,
    LlmRequest llmRequest,
  ) async* {
    final LlmAgent agent = invocationContext.agent as LlmAgent;
    final List<Event> events = invocationContext.getEvents(currentBranch: true);
    if (events.isEmpty) {
      return;
    }

    final Map<String, ToolConfirmation> confirmationByRequestId =
        <String, ToolConfirmation>{};
    int confirmationEventIndex = -1;

    for (int i = events.length - 1; i >= 0; i -= 1) {
      final Event event = events[i];
      if (event.author != 'user') {
        continue;
      }

      final List<FunctionResponse> responses = event.getFunctionResponses();
      if (responses.isEmpty) {
        return;
      }

      for (final FunctionResponse response in responses) {
        if (response.name !=
            flow_functions.requestConfirmationFunctionCallName) {
          continue;
        }
        final String? requestId = response.id;
        if (requestId == null || requestId.isEmpty) {
          continue;
        }
        final ToolConfirmation? confirmation = _parseToolConfirmation(
          response.response,
        );
        if (confirmation != null) {
          confirmationByRequestId[requestId] = confirmation;
        }
      }
      confirmationEventIndex = i;
      break;
    }

    if (confirmationByRequestId.isEmpty) {
      return;
    }

    for (int i = events.length - 2; i >= 0; i -= 1) {
      final Event event = events[i];
      final List<FunctionCall> calls = event.getFunctionCalls();
      if (calls.isEmpty) {
        continue;
      }

      final Map<String, ToolConfirmation> toolsToResumeWithConfirmation =
          <String, ToolConfirmation>{};
      final Map<String, FunctionCall> toolsToResumeWithArgs =
          <String, FunctionCall>{};

      for (final FunctionCall call in calls) {
        final String? requestId = call.id;
        if (requestId == null ||
            !confirmationByRequestId.containsKey(requestId)) {
          continue;
        }

        final FunctionCall? originalFunctionCall = _readOriginalFunctionCall(
          call.args,
        );
        final String? originalId = originalFunctionCall?.id;
        if (originalFunctionCall == null ||
            originalId == null ||
            originalId.isEmpty) {
          continue;
        }

        toolsToResumeWithConfirmation[originalId] =
            confirmationByRequestId[requestId]!;
        toolsToResumeWithArgs[originalId] = originalFunctionCall;
      }

      if (toolsToResumeWithConfirmation.isEmpty) {
        continue;
      }

      for (int j = events.length - 1; j > confirmationEventIndex; j -= 1) {
        final List<FunctionResponse> responses = events[j]
            .getFunctionResponses();
        if (responses.isEmpty) {
          continue;
        }
        for (final FunctionResponse response in responses) {
          final String? responseId = response.id;
          if (responseId == null) {
            continue;
          }
          toolsToResumeWithConfirmation.remove(responseId);
          toolsToResumeWithArgs.remove(responseId);
        }
        if (toolsToResumeWithConfirmation.isEmpty) {
          break;
        }
      }

      if (toolsToResumeWithConfirmation.isEmpty) {
        continue;
      }

      final List<BaseTool> tools = await agent.canonicalTools(
        ReadonlyContext(invocationContext),
      );
      final Map<String, BaseTool> toolsDict = <String, BaseTool>{
        for (final BaseTool tool in tools) tool.name: tool,
      };

      final Event? functionResponseEvent = await flow_functions
          .handleFunctionCallListAsync(
            invocationContext,
            toolsToResumeWithArgs.values.toList(growable: false),
            toolsDict,
            filters: toolsToResumeWithConfirmation.keys.toSet(),
            toolConfirmationDict: toolsToResumeWithConfirmation,
          );
      if (functionResponseEvent != null) {
        yield functionResponseEvent;
      }
      return;
    }
  }

  FunctionCall? _readOriginalFunctionCall(Map<String, dynamic> args) {
    final Object? raw = args['originalFunctionCall'];
    if (raw is! Map) {
      return null;
    }

    final Object? nameRaw = raw['name'];
    if (nameRaw is! String || nameRaw.isEmpty) {
      return null;
    }

    final Map<String, dynamic> copied = <String, dynamic>{
      for (final MapEntry<Object?, Object?> entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };

    final Object? idRaw = copied['id'];
    final Object? argsRaw = copied['args'];
    return FunctionCall(
      name: nameRaw,
      id: idRaw is String && idRaw.isNotEmpty ? idRaw : null,
      args: argsRaw is Map
          ? <String, dynamic>{
              for (final MapEntry<Object?, Object?> entry in argsRaw.entries)
                if (entry.key is String) entry.key as String: entry.value,
            }
          : <String, dynamic>{},
    );
  }

  ToolConfirmation? _parseToolConfirmation(Map<String, dynamic> payload) {
    Object? source = payload;
    if (payload.length == 1 && payload.containsKey('response')) {
      source = payload['response'];
      if (source is String) {
        try {
          source = jsonDecode(source);
        } catch (_) {
          source = <String, dynamic>{'confirmed': source == 'true'};
        }
      }
    }

    if (source is ToolConfirmation) {
      return ToolConfirmation(
        hint: source.hint,
        payload: source.payload,
        confirmed: source.confirmed,
      );
    }

    if (source is! Map) {
      return null;
    }

    final Map<Object?, Object?> map = source;
    final Object? confirmedRaw = map['confirmed'];
    bool? confirmed;
    if (confirmedRaw is bool) {
      confirmed = confirmedRaw;
    } else if (confirmedRaw is String) {
      if (confirmedRaw.toLowerCase() == 'true') {
        confirmed = true;
      } else if (confirmedRaw.toLowerCase() == 'false') {
        confirmed = false;
      }
    }

    return ToolConfirmation(
      hint: map['hint'] is String ? map['hint'] as String : null,
      payload: map['payload'],
      confirmed: confirmed,
    );
  }
}
