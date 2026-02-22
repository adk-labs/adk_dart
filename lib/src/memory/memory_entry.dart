import '../types/content.dart';

class MemoryEntry {
  MemoryEntry({
    required this.content,
    Map<String, Object?>? customMetadata,
    this.id,
    this.author,
    this.timestamp,
  }) : customMetadata = customMetadata ?? <String, Object?>{};

  Content content;
  Map<String, Object?> customMetadata;
  String? id;
  String? author;
  String? timestamp;

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
