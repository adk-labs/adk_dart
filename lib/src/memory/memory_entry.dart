/// Memory entry model used by memory services.
library;

import '../types/content.dart';

/// One memory item with content and optional metadata.
class MemoryEntry {
  /// Creates a memory entry.
  MemoryEntry({
    required this.content,
    Map<String, Object?>? customMetadata,
    this.id,
    this.author,
    this.timestamp,
  }) : customMetadata = customMetadata ?? <String, Object?>{};

  /// Content payload stored in memory.
  Content content;

  /// Provider-specific metadata attached to this memory.
  Map<String, Object?> customMetadata;

  /// Optional memory identifier.
  String? id;

  /// Optional source author.
  String? author;

  /// Optional source timestamp string.
  String? timestamp;

  /// Returns a copied memory entry with optional overrides.
  MemoryEntry copyWith({
    Content? content,
    Map<String, Object?>? customMetadata,
    Object? id = _sentinel,
    Object? author = _sentinel,
    Object? timestamp = _sentinel,
  }) {
    return MemoryEntry(
      content: content ?? this.content.copyWith(),
      customMetadata:
          customMetadata ?? Map<String, Object?>.from(this.customMetadata),
      id: identical(id, _sentinel) ? this.id : id as String?,
      author: identical(author, _sentinel) ? this.author : author as String?,
      timestamp: identical(timestamp, _sentinel)
          ? this.timestamp
          : timestamp as String?,
    );
  }
}

const Object _sentinel = Object();
