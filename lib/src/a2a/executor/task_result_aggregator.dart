/// Helpers for aggregating task status from streamed A2A events.
library;

import '../protocol.dart';

/// Aggregates task status updates into a single terminal summary.
class TaskResultAggregator {
  A2aTaskState _taskState = A2aTaskState.working;
  A2aMessage? _taskStatusMessage;

  /// Processes one streamed [event] and updates aggregate status.
  void processEvent(A2aEvent event) {
    if (event is! A2aTaskStatusUpdateEvent) {
      return;
    }

    if (event.status.state == A2aTaskState.failed) {
      _taskState = A2aTaskState.failed;
      _taskStatusMessage = event.status.message;
    } else if (event.status.state == A2aTaskState.authRequired &&
        _taskState != A2aTaskState.failed) {
      _taskState = A2aTaskState.authRequired;
      _taskStatusMessage = event.status.message;
    } else if (event.status.state == A2aTaskState.inputRequired &&
        _taskState != A2aTaskState.failed &&
        _taskState != A2aTaskState.authRequired) {
      _taskState = A2aTaskState.inputRequired;
      _taskStatusMessage = event.status.message;
    } else if (_taskState == A2aTaskState.working) {
      _taskStatusMessage = event.status.message;
    }

    event.status.state = A2aTaskState.working;
  }

  /// Aggregated task state.
  A2aTaskState get taskState => _taskState;

  /// Last observed task status message.
  A2aMessage? get taskStatusMessage => _taskStatusMessage;
}
