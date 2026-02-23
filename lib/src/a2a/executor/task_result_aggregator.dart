import '../protocol.dart';

class TaskResultAggregator {
  A2aTaskState _taskState = A2aTaskState.working;
  A2aMessage? _taskStatusMessage;

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

  A2aTaskState get taskState => _taskState;

  A2aMessage? get taskStatusMessage => _taskStatusMessage;
}
