import 'dart:async';
import 'dart:collection';

import '../types/content.dart';

class LiveRequest {
  LiveRequest({
    this.content,
    this.blob,
    this.activityStart = false,
    this.activityEnd = false,
    this.close = false,
  });

  Content? content;
  Object? blob;
  bool activityStart;
  bool activityEnd;
  bool close;
}

class LiveRequestQueue {
  final Queue<LiveRequest> _queue = Queue<LiveRequest>();
  Completer<LiveRequest>? _pending;

  void close() {
    _enqueue(LiveRequest(close: true));
  }

  void sendContent(Content content) {
    _enqueue(LiveRequest(content: content));
  }

  void sendRealtime(Object blob) {
    _enqueue(LiveRequest(blob: blob));
  }

  void sendActivityStart() {
    _enqueue(LiveRequest(activityStart: true));
  }

  void sendActivityEnd() {
    _enqueue(LiveRequest(activityEnd: true));
  }

  void send(LiveRequest request) {
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
