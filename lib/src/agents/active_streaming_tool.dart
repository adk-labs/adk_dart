/// Models active streaming tool execution state.
library;

import 'dart:async';

import 'live_request_queue.dart';

/// Tracks the active async task and optional live stream for a tool call.
class ActiveStreamingTool {
  /// Creates an active streaming tool descriptor.
  ActiveStreamingTool({
    this.task,
    this.stream,
    this.arguments,
    this.onCancel,
  });

  /// In-flight task for the tool call.
  Future<Object?>? task;

  /// Queue for streaming tool updates.
  LiveRequestQueue? stream;

  /// Arguments used when starting this streaming tool call.
  Map<String, dynamic>? arguments;

  /// Optional cancellation callback for the active stream.
  FutureOr<void> Function()? onCancel;
}
