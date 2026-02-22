import 'dart:async';

import 'a2a_message.dart';

class InMemoryA2ARouter {
  final StreamController<A2AMessage> _controller =
      StreamController<A2AMessage>.broadcast();

  Stream<A2AMessage> messagesFor(String agentName) {
    return _controller.stream.where((A2AMessage message) {
      return message.toAgent == agentName;
    });
  }

  void send(A2AMessage message) {
    if (_controller.isClosed) {
      throw StateError('A2A router is already closed.');
    }
    _controller.add(message);
  }

  Future<void> close() => _controller.close();
}
