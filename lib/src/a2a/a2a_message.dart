/// In-memory message model for A2A router flows.
library;

import '../platform/time.dart';

/// A routed message exchanged between two local agents.
class A2AMessage {
  /// Creates an A2A message.
  A2AMessage({
    required this.fromAgent,
    required this.toAgent,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? getUtcNow();

  /// Sender agent name.
  final String fromAgent;

  /// Recipient agent name.
  final String toAgent;

  /// Message text payload.
  final String content;

  /// Message creation timestamp in UTC.
  final DateTime timestamp;
}
