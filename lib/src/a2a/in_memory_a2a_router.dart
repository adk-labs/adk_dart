/// In-memory broadcast router for local A2A message exchange.
library;

import 'dart:async';

import 'a2a_message.dart';

/// Routes [A2AMessage] payloads between local agent names.
class InMemoryA2ARouter {
  final StreamController<A2AMessage> _controller =
      StreamController<A2AMessage>.broadcast();

  /// Returns a stream of messages addressed to [agentName].
  Stream<A2AMessage> messagesFor(String agentName) {
    return _controller.stream.where((A2AMessage message) {
      return message.toAgent == agentName;
    });
  }

  /// Sends [message] to all subscribers.
  void send(A2AMessage message) {
    if (_controller.isClosed) {
      throw StateError('A2A router is already closed.');
    }
    _controller.add(message);
  }

  /// Closes this router and all underlying streams.
  Future<void> close() => _controller.close();
}
