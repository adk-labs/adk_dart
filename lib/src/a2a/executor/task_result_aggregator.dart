/// Helpers for aggregating task status from streamed A2A events.
library;

import '../../events/abort_events.dart';
import '../converters/utils.dart';
import '../protocol.dart';

bool _isCanceledStatusEvent(A2aTaskStatusUpdateEvent event) {
  if (event.status.state == A2aTaskState.canceled) {
    return true;
  }
  if (event.status.state != A2aTaskState.failed) {
    return false;
  }
  final String errorCodeKey = getAdkMetadataKey('error_code');
  final Map<String, Object?> statusMetadata =
      event.status.message?.metadata ?? const <String, Object?>{};
  final Map<String, Object?> eventMetadata = event.metadata;
  final Object? errorCode =
      eventMetadata[errorCodeKey] ?? statusMetadata[errorCodeKey];
  return errorCode == invocationAbortedErrorCode;
}

/// Aggregates task status updates into a single terminal summary.
class TaskResultAggregator {
  A2aTaskState _taskState = A2aTaskState.working;
  A2aMessage? _taskStatusMessage;
  bool _failed = false;
  A2aMessage? _failureMessage;

  /// Processes one streamed [event] and updates aggregate status.
  void processEvent(A2aEvent event) {
    if (event is! A2aTaskStatusUpdateEvent) {
      return;
    }

    if (_isCanceledStatusEvent(event)) {
      _taskState = A2aTaskState.canceled;
      _taskStatusMessage = event.status.message;
      _failed = false;
      _failureMessage = null;
    } else if (_taskState == A2aTaskState.canceled) {
      // Canceled is terminal and highest priority.
    } else if (event.status.state == A2aTaskState.failed) {
      _failed = true;
      _failureMessage = event.status.message;
    } else if (event.status.state == A2aTaskState.authRequired) {
      _taskState = A2aTaskState.authRequired;
      _taskStatusMessage = event.status.message;
    } else if (event.status.state == A2aTaskState.inputRequired &&
        _taskState != A2aTaskState.authRequired) {
      _taskState = A2aTaskState.inputRequired;
      _taskStatusMessage = event.status.message;
    } else if (_taskState == A2aTaskState.working) {
      _taskStatusMessage = event.status.message;
    }

    event.status.state = A2aTaskState.working;
  }

  /// Retains only unresolved failure [messages] after error-recovery tracking.
  void keepFailures(List<A2aMessage?> messages) {
    if (_taskState == A2aTaskState.canceled) {
      _failed = false;
      _failureMessage = null;
      return;
    }
    _failed = messages.isNotEmpty;
    _failureMessage = messages.isNotEmpty ? messages.last : null;
  }

  /// Aggregated task state.
  A2aTaskState get taskState {
    if (_taskState == A2aTaskState.canceled) {
      return A2aTaskState.canceled;
    }
    return _failed ? A2aTaskState.failed : _taskState;
  }

  /// Last observed task status message.
  A2aMessage? get taskStatusMessage {
    if (_taskState == A2aTaskState.canceled) {
      return _taskStatusMessage;
    }
    return _failed ? _failureMessage : _taskStatusMessage;
  }
}
