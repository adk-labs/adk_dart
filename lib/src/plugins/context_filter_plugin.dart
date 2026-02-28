import 'dart:io';

import '../agents/callback_context.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../types/content.dart';
import 'base_plugin.dart';

int _adjustSplitIndexToAvoidOrphanedFunctionResponses(
  List<Content> contents,
  int splitIndex,
) {
  final Set<String> neededCallIds = <String>{};

  for (int i = contents.length - 1; i >= 0; i -= 1) {
    final List<Part> parts = contents[i].parts;
    for (int j = parts.length - 1; j >= 0; j -= 1) {
      final Part part = parts[j];
      final String? responseId = part.functionResponse?.id;
      if (responseId != null && responseId.isNotEmpty) {
        neededCallIds.add(responseId);
      }
      final String? callId = part.functionCall?.id;
      if (callId != null && callId.isNotEmpty) {
        neededCallIds.remove(callId);
      }
    }

    if (i <= splitIndex && neededCallIds.isEmpty) {
      return i;
    }
  }

  return 0;
}

bool _isFunctionResponseContent(Content content) {
  return content.parts.any((Part part) => part.functionResponse != null);
}

bool _isHumanUserContent(Content content) {
  return content.role == 'user' && !_isFunctionResponseContent(content);
}

List<int> _getInvocationStartIndices(List<Content> contents) {
  final List<int> indices = <int>[];
  bool previousWasHumanUser = false;

  for (int i = 0; i < contents.length; i += 1) {
    final bool isHumanUser = _isHumanUserContent(contents[i]);
    if (isHumanUser && !previousWasHumanUser) {
      indices.add(i);
    }
    previousWasHumanUser = isHumanUser;
  }
  return indices;
}

class ContextFilterPlugin extends BasePlugin {
  ContextFilterPlugin({
    int? numInvocationsToKeep,
    List<Content> Function(List<Content> contents)? customFilter,
    super.name = 'context_filter_plugin',
  }) : _numInvocationsToKeep = numInvocationsToKeep,
       _customFilter = customFilter;

  final int? _numInvocationsToKeep;
  final List<Content> Function(List<Content> contents)? _customFilter;

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    try {
      List<Content> contents = llmRequest.contents;

      final int? keep = _numInvocationsToKeep;
      if (keep != null && keep > 0) {
        final List<int> invocationStartIndices = _getInvocationStartIndices(
          contents,
        );
        if (invocationStartIndices.length > keep) {
          int splitIndex =
              invocationStartIndices[invocationStartIndices.length - keep];
          splitIndex = _adjustSplitIndexToAvoidOrphanedFunctionResponses(
            contents,
            splitIndex,
          );
          contents = contents.sublist(splitIndex);
        }
      }

      if (_customFilter != null) {
        contents = _customFilter(contents);
      }

      llmRequest.contents = contents;
    } catch (error) {
      stderr.writeln('Failed to reduce context for request: $error');
    }

    return null;
  }
}
