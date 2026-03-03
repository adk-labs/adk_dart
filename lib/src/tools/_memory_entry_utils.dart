/// Helpers for extracting renderable text from memory entries.
library;

import '../memory/memory_entry.dart';

/// The concatenated text from all text parts in [memory].
String extractText(MemoryEntry memory, {String splitter = ' '}) {
  if (memory.content.parts.isEmpty) {
    return '';
  }
  final List<String> chunks = <String>[];
  for (final part in memory.content.parts) {
    final String? text = part.text;
    if (text != null && text.isNotEmpty) {
      chunks.add(text);
    }
  }
  return chunks.join(splitter);
}
