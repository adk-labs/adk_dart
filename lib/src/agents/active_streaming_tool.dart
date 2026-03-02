/// Models active streaming tool execution state.
library;

import 'live_request_queue.dart';

/// Tracks the active async task and optional live stream for a tool call.
class ActiveStreamingTool {
  /// Creates an active streaming tool descriptor.
  ActiveStreamingTool({this.task, this.stream});

  /// In-flight task for the tool call.
  Future<Object?>? task;

  /// Queue for streaming tool updates.
  LiveRequestQueue? stream;
}
