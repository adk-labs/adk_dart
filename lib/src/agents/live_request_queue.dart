/// Queue models for live request streaming.
library;

import 'dart:async';
import 'dart:collection';

import '../types/content.dart';

/// Marker indicating the start of a live activity segment.
class LiveActivityStart {
  /// Creates a start marker.
  const LiveActivityStart();
}

/// Marker indicating the end of a live activity segment.
class LiveActivityEnd {
  /// Creates an end marker.
  const LiveActivityEnd();
}

/// A single queued live request payload.
class LiveRequest {
  /// Creates a live request envelope.
  LiveRequest({
    this.content,
    this.blob,
    this.activityStart,
    this.activityEnd,
    this.close = false,
  });

  /// Structured content payload.
  Content? content;

  /// Opaque realtime blob payload.
  Object? blob;

  /// Activity-start marker payload.
  LiveActivityStart? activityStart;

  /// Activity-end marker payload.
  LiveActivityEnd? activityEnd;

  /// Whether this request closes the queue.
  bool close;
}

/// In-memory FIFO queue for live requests.
class LiveRequestQueue {
  /// Creates an empty live-request queue.
  LiveRequestQueue();

  final Queue<LiveRequest> _queue = Queue<LiveRequest>();
  Completer<LiveRequest>? _pending;
  bool _closed = false;

  /// Closes the queue and enqueues a terminal request.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _enqueue(LiveRequest(close: true));
  }

  /// Enqueues [content] as a live request.
  void sendContent(Content content) {
    if (_closed) {
      return;
    }
    _enqueue(LiveRequest(content: content));
  }

  /// Enqueues raw realtime [blob] data.
  void sendRealtime(Object blob) {
    if (_closed) {
      return;
    }
    _enqueue(LiveRequest(blob: blob));
  }

  /// Enqueues a live activity-start marker.
  void sendActivityStart() {
    if (_closed) {
      return;
    }
    _enqueue(LiveRequest(activityStart: const LiveActivityStart()));
  }

  /// Enqueues a live activity-end marker.
  void sendActivityEnd() {
    if (_closed) {
      return;
    }
    _enqueue(LiveRequest(activityEnd: const LiveActivityEnd()));
  }

  /// Enqueues [request] unless the queue is closed.
  void send(LiveRequest request) {
    if (request.close) {
      close();
      return;
    }
    if (_closed) {
      return;
    }
    _enqueue(request);
  }

  /// Returns the next queued request, waiting when empty.
  Future<LiveRequest> get() {
    if (_queue.isNotEmpty) {
      return Future<LiveRequest>.value(_queue.removeFirst());
    }

    _pending ??= Completer<LiveRequest>();
    return _pending!.future;
  }

  void _enqueue(LiveRequest request) {
    final Completer<LiveRequest>? pending = _pending;
    if (pending != null && !pending.isCompleted) {
      _pending = null;
      pending.complete(request);
      return;
    }

    _queue.addLast(request);
  }
}
