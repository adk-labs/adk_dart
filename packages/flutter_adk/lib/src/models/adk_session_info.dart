/// Metadata model representing a chat or multi-agent conversation session.
class AdkSessionInfo {
  /// Creates an [AdkSessionInfo].
  const AdkSessionInfo({
    required this.id,
    required this.title,
    this.createdAt,
    this.updatedAt,
    this.lastMessagePreview,
    this.messageCount = 0,
    this.metadata = const <String, dynamic>{},
  });

  /// Unique session identifier.
  final String id;

  /// Human-readable title of the session.
  final String title;

  /// Timestamp when the session was created.
  final DateTime? createdAt;

  /// Timestamp of the latest message or update in this session.
  final DateTime? updatedAt;

  /// Snippet of the last exchange for list previews.
  final String? lastMessagePreview;

  /// Total number of messages stored in this session.
  final int messageCount;

  /// Custom metadata attributes.
  final Map<String, dynamic> metadata;

  /// Copies this [AdkSessionInfo] with updated values.
  AdkSessionInfo copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? lastMessagePreview,
    int? messageCount,
    Map<String, dynamic>? metadata,
  }) {
    return AdkSessionInfo(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      messageCount: messageCount ?? this.messageCount,
      metadata: metadata ?? this.metadata,
    );
  }
}
