/// Helpers for extracting and finalizing long-running A2A function events.
library;

import '../../events/event.dart';
import '../../flows/llm_flows/functions.dart';
import '../../platform/uuid.dart';
import '../../types/content.dart';
import '../protocol.dart';
import 'part_converter.dart';
import 'utils.dart';

/// Tracks long-running function calls and matching responses across ADK events.
class LongRunningFunctions {
  /// Creates a long-running function accumulator.
  LongRunningFunctions({GenAIPartToA2APartConverter? partConverter})
    : _partConverter = partConverter ?? convertGenaiPartToA2aPart;

  final List<Part> _parts = <Part>[];
  final Set<String> _longRunningToolIds = <String>{};
  final GenAIPartToA2APartConverter _partConverter;

  A2aTaskState _taskState = A2aTaskState.inputRequired;

  /// Whether any long-running tool calls were observed.
  bool hasLongRunningFunctionCalls() => _longRunningToolIds.isNotEmpty;

  /// Returns a copy of [event] with tracked long-running parts removed.
  Event processEvent(Event event) {
    final Content? content = event.content;
    if (content == null || content.parts.isEmpty) {
      return event.copyWith();
    }

    final List<Part> keptParts = <Part>[];
    for (final Part part in content.parts) {
      bool shouldRemove = false;

      final FunctionCall? functionCall = part.functionCall;
      if (functionCall != null &&
          functionCall.id != null &&
          event.longRunningToolIds?.contains(functionCall.id) == true) {
        if (event.partial != true) {
          _parts.add(part.copyWith());
          _longRunningToolIds.add(functionCall.id!);
        }
        shouldRemove = true;
      }

      final FunctionResponse? functionResponse = part.functionResponse;
      if (!shouldRemove &&
          functionResponse != null &&
          functionResponse.id != null &&
          _longRunningToolIds.contains(functionResponse.id)) {
        if (event.partial != true) {
          _parts.add(part.copyWith());
        }
        shouldRemove = true;
      }

      if (!shouldRemove) {
        keptParts.add(part.copyWith());
      }
    }

    return event.copyWith(content: content.copyWith(parts: keptParts));
  }

  /// Creates the terminal A2A task event for the accumulated long-running work.
  A2aTaskStatusUpdateEvent? createLongRunningFunctionCallEvent({
    required String taskId,
    required String contextId,
  }) {
    if (_longRunningToolIds.isEmpty) {
      return null;
    }

    final List<A2aPart> a2aParts = _toA2aParts();
    if (a2aParts.isEmpty) {
      return null;
    }

    return A2aTaskStatusUpdateEvent(
      taskId: taskId,
      contextId: contextId,
      finalEvent: true,
      status: A2aTaskStatus(
        state: _taskState,
        message: A2aMessage(
          messageId: newUuid(),
          role: A2aRole.agent,
          parts: a2aParts,
        ),
      ),
    );
  }

  List<A2aPart> _toA2aParts() {
    final List<A2aPart> outputParts = <A2aPart>[];
    for (final Part part in _parts) {
      final Object? converted = _partConverter(part);
      final List<A2aPart> a2aParts = <A2aPart>[];
      if (converted is A2aPart) {
        a2aParts.add(converted);
      } else if (converted is List<A2aPart>) {
        a2aParts.addAll(converted);
      }

      for (final A2aPart a2aPart in a2aParts) {
        _markLongRunningFunctionCall(a2aPart);
        outputParts.add(a2aPart);
      }
    }
    return outputParts;
  }

  void _markLongRunningFunctionCall(A2aPart a2aPart) {
    final A2aDataPart? dataPart = a2aPart.dataPart;
    if (dataPart == null) {
      return;
    }
    if (dataPart.metadata[getAdkMetadataKey(a2aDataPartMetadataTypeKey)] !=
        a2aDataPartMetadataTypeFunctionCall) {
      return;
    }

    dataPart.metadata[getAdkMetadataKey(a2aDataPartMetadataIsLongRunningKey)] =
        true;
    if (dataPart.data['name'] == requestEucFunctionCallName) {
      _taskState = A2aTaskState.authRequired;
      return;
    }
    _taskState = A2aTaskState.inputRequired;
  }
}
