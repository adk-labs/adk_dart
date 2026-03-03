/// Content-part helpers for multimodal filtering.
library;

import '../types/content.dart';

/// Whether [part] contains audio data.
bool isAudioPart(Part part) {
  return (part.inlineData != null &&
          part.inlineData!.mimeType.toLowerCase().startsWith('audio/')) ||
      (part.fileData != null &&
          (part.fileData!.mimeType ?? '').toLowerCase().startsWith('audio/'));
}

/// The [content] copy without audio parts.
///
/// Returns `null` when [content] is empty or all parts are audio.
Content? filterAudioParts(Content content) {
  if (content.parts.isEmpty) {
    return null;
  }
  final List<Part> filtered = content.parts
      .where((Part part) => !isAudioPart(part))
      .map((Part part) => part.copyWith())
      .toList(growable: false);
  if (filtered.isEmpty) {
    return null;
  }
  return Content(role: content.role, parts: filtered);
}
