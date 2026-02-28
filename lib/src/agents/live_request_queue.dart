import 'dart:async';
import 'dart:collection';

import '../types/content.dart';

class LiveActivityStart {
  const LiveActivityStart();
}

class LiveActivityEnd {
  const LiveActivityEnd();
}

class LiveRequest {
  LiveRequest({
    this.content,
    this.blob,
    this.activityStart,
    this.activityEnd,
    this.close = false,
  });

  Content? content;
  Object? blob;
  LiveActivityStart? activityStart;
  LiveActivityEnd? activityEnd;
  bool close;
}

class LiveRequestQueue {
  final Queue<LiveRequest> _queue = Queue<LiveRequest>();
  Completer<LiveRequest>? _pending;
  bool _closed = false;

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _enqueue(LiveRequest(close: true));
  }

  void sendContent(Content content) {
    if (_closed) {
      return;
    }
    _enqueue(LiveRequest(content: content));
  }

  void sendRealtime(Object blob) {
    if (_closed) {
      return;
    }
    _enqueue(LiveRequest(blob: blob));
  }

  void sendActivityStart() {
    if (_closed) {
      return;
    }
    _enqueue(LiveRequest(activityStart: const LiveActivityStart()));
  }

  void sendActivityEnd() {
    if (_closed) {
      return;
    }
    _enqueue(LiveRequest(activityEnd: const LiveActivityEnd()));
  }

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
