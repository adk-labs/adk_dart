class A2AMessage {
  A2AMessage({
    required this.fromAgent,
    required this.toAgent,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  final String fromAgent;
  final String toAgent;
  final String content;
  final DateTime timestamp;
}
